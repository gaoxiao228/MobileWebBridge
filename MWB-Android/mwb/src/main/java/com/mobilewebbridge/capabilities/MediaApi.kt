package com.mobilewebbridge.capabilities

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Base64
import androidx.core.content.FileProvider
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBResult
import org.json.JSONArray
import org.json.JSONObject
import wendu.dsbridge.CompletionHandler
import java.io.ByteArrayOutputStream
import java.io.File

/** 系统媒体能力；文件读写仅在 MWB 私有缓存目录内进行。 */
class MediaApi(private val activity: MWBActivity) {
    companion object { private const val PICK = 4201; private const val CAMERA = 4202; private const val PERMISSION = 4203; private const val PHOTO_PERMISSION = 4204 }
    private var pendingImage: CompletionHandler<Any>? = null
    private var pendingPermission: CompletionHandler<Any>? = null
    private var pendingCamera: Boolean = false
    private var pendingSave: Pair<Bitmap, CompletionHandler<Any>>? = null
    private var pendingImageCount = 1

    /** Activity 销毁时丢弃旧页面回调，重建后的 WebView 不会继承它们。 */
    fun dispose() {
        pendingImage = null
        pendingPermission = null
        pendingSave = null
        pendingCamera = false
    }

    private val imageDir: File get() = File(activity.cacheDir, "mwb").apply { mkdirs() }
    private fun result(cb: CompletionHandler<Any>, value: Any? = null) { cb.complete(MWBResult.success(value)) }
    private fun error(cb: CompletionHandler<Any>, code: Int, text: String) { cb.complete(MWBResult.failure(code, text)) }
    private fun params(arg: Any): JSONObject? = arg as? JSONObject

    private fun imageBytes(text: String?): ByteArray? = try {
        if (text.isNullOrBlank()) null else Base64.decode(text.substringAfter("base64,", text), Base64.DEFAULT)
    } catch (_: IllegalArgumentException) { null }

    private fun decode(text: String?): Bitmap? = imageBytes(text)?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }

    private fun saveCache(bitmap: Bitmap): File {
        val file = File.createTempFile("image-", ".jpg", imageDir)
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        return file
    }

    private fun trustedFile(path: String?): File? {
        if (path.isNullOrBlank()) return null
        val file = File(path.removePrefix("file://")).canonicalFile
        return file.takeIf { it.isFile && it.path.startsWith(imageDir.canonicalPath + File.separator) }
    }

    fun compressImage(arg: Any, cb: CompletionHandler<Any>) {
        val p = params(arg)
        val bitmap = decode(p?.optString("base64Image")) ?: return error(cb, -1001, "Invalid image")
        val limit = p?.optInt("maxLength", 1024 * 1024)?.coerceAtLeast(1) ?: 1024 * 1024
        var bytes = ByteArray(0)
        for (quality in 90 downTo 10 step 10) {
            bytes = ByteArrayOutputStream().use { stream -> bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream); stream.toByteArray() }
            if (bytes.size <= limit) break
        }
        if (bytes.size > limit) return error(cb, -1002, "Image cannot fit maxLength")
        result(cb, JSONObject().put("base64Image", Base64.encodeToString(bytes, Base64.NO_WRAP))
            .put("imageWidth", bitmap.width).put("imageHeight", bitmap.height))
    }

    fun scanCode(arg: Any, cb: CompletionHandler<Any>) {
        val p = params(arg)
        if (p?.has("hideAlbum") == true && !p.optBoolean("hideAlbum"))
            return error(cb, -1004, "Album scanning is unavailable on Android")
        val requested = p?.optJSONArray("scanType")
        val types = if (requested == null) setOf("qrCode", "barCode")
            else (0 until requested.length()).map(requested::optString).toSet()
        if (types.isEmpty() || types.any { it !in setOf("qrCode", "barCode") })
            return error(cb, -1001, "Invalid scan type")
        val oneDimensional = intArrayOf(Barcode.FORMAT_CODE_128, Barcode.FORMAT_CODE_39,
            Barcode.FORMAT_CODE_93, Barcode.FORMAT_CODABAR, Barcode.FORMAT_EAN_13,
            Barcode.FORMAT_EAN_8, Barcode.FORMAT_ITF, Barcode.FORMAT_UPC_A, Barcode.FORMAT_UPC_E)
        val formats = when (types) {
            setOf("qrCode") -> intArrayOf(Barcode.FORMAT_QR_CODE)
            setOf("barCode") -> oneDimensional
            else -> intArrayOf(Barcode.FORMAT_QR_CODE, *oneDimensional)
        }
        val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(formats[0], *formats.drop(1).toIntArray()).build()
        activity.runOnUiThread {
            // Google Code Scanner 自行持有相机权限；无 Play Services 时明确返回失败。
            GmsBarcodeScanning.getClient(activity, options).startScan()
                .addOnSuccessListener { barcode ->
                    val type = if (barcode.format == Barcode.FORMAT_QR_CODE) "qrCode" else "barCode"
                    result(cb, JSONObject().put("scanType", type).put("code", barcode.rawValue ?: ""))
                }
                .addOnCanceledListener { error(cb, -1007, "Cancelled") }
                .addOnFailureListener { error(cb, -1004, "Scanner unavailable") }
        }
    }

    fun saveImage(arg: Any, cb: CompletionHandler<Any>) {
        val bitmap = decode(params(arg)?.optString("base64Image")) ?: return error(cb, -1001, "Invalid image")
        activity.runOnUiThread {
            if (Build.VERSION.SDK_INT < 29 && activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                if (pendingSave != null) return@runOnUiThread error(cb, -1008, "Photo permission request is busy")
                pendingSave = bitmap to cb
                activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), PHOTO_PERMISSION)
                return@runOnUiThread
            }
            writePhoto(bitmap, cb)
        }
    }

    private fun writePhoto(bitmap: Bitmap, cb: CompletionHandler<Any>) {
            try {
                val values = android.content.ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, "mwb-${System.currentTimeMillis()}.jpg")
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    if (Build.VERSION.SDK_INT >= 29) put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/MWB")
                }
                val uri = activity.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: return error(cb, -1002, "Cannot save image")
                activity.contentResolver.openOutputStream(uri)?.use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
                    ?: return error(cb, -1002, "Cannot save image")
                result(cb)
            } catch (_: SecurityException) { error(cb, -1008, "Photo permission denied") }
            catch (_: Exception) { error(cb, -1002, "Cannot save image") }
    }

    fun chooseImage(arg: Any, cb: CompletionHandler<Any>) {
        val parameters = params(arg)
        val source = parameters?.optString("sourceType", "all") ?: "all"
        if (source !in setOf("album", "camera", "all")) return error(cb, -1001, "Invalid image source")
        val count = parameters?.optInt("count", 1) ?: 1
        if (count !in 1..20) return error(cb, -1001, "Invalid image count")
        val sizes = parameters?.optJSONArray("sizeType")
        if (sizes != null && (0 until sizes.length()).any { sizes.optString(it) !in setOf("original", "compressed") })
            return error(cb, -1001, "Invalid image size type")
        activity.runOnUiThread {
            if (pendingImage != null) return@runOnUiThread error(cb, -1008, "Image picker is busy")
            pendingImage = cb
            pendingImageCount = count
            when (source) {
                "camera" -> startCamera()
                "album" -> startAlbum()
                else -> android.app.AlertDialog.Builder(activity)
                    .setItems(arrayOf("相册", "相机")) { _, index -> if (index == 0) startAlbum() else startCamera() }
                    .setOnCancelListener { pendingImage = null; error(cb, -1007, "Cancelled") }
                    .show()
            }
        }
    }

    private fun startAlbum() {
        val cb = pendingImage ?: return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, pendingImageCount > 1)
        try { activity.startActivityForResult(intent, PICK) }
        catch (_: Exception) { pendingImage = null; error(cb, -1004, "Image picker unavailable") }
    }

    private fun startCamera() {
        val cb = pendingImage ?: return
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            pendingCamera = true
            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION)
            return
        }
        try { activity.startActivityForResult(Intent(MediaStore.ACTION_IMAGE_CAPTURE), CAMERA) }
        catch (_: Exception) { pendingImage = null; error(cb, -1004, "Camera unavailable") }
    }

    fun checkCameraPermission(cb: CompletionHandler<Any>) {
        activity.runOnUiThread {
            if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
                result(cb, JSONObject().put("grant", true))
            else if (pendingPermission != null) error(cb, -1008, "Permission request is busy")
            else { pendingPermission = cb; activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION) }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grants: IntArray) {
        if (requestCode == PHOTO_PERMISSION) {
            val save = pendingSave ?: return
            pendingSave = null
            if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) writePhoto(save.first, save.second)
            else error(save.second, -1008, "Photo permission denied")
            return
        }
        if (requestCode != PERMISSION) return
        val granted = grants.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingPermission?.let { result(it, JSONObject().put("grant", granted)) }
        pendingPermission = null
        if (pendingCamera) {
            pendingCamera = false
            if (granted) startCamera() else pendingImage?.let { error(it, -1008, "Camera permission denied") }.also { pendingImage = null }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK && requestCode != CAMERA) return
        val cb = pendingImage ?: return
        pendingImage = null
        if (resultCode != Activity.RESULT_OK) return error(cb, -1007, "Cancelled")
        try {
            val images = JSONArray()
            if (requestCode == CAMERA) {
                val bitmap = data?.extras?.get("data") as? Bitmap ?: return error(cb, -1002, "Camera returned no image")
                val path = saveCache(bitmap).absolutePath
                images.put(JSONObject().put("original", path).put("compressed", path))
            } else {
                val uris = mutableListOf<Uri>()
                data?.data?.let(uris::add)
                data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
                for (uri in uris.take(pendingImageCount)) {
                    val original = File.createTempFile("original-", ".img", imageDir)
                    activity.contentResolver.openInputStream(uri)?.use { input -> original.outputStream().use(input::copyTo) } ?: continue
                    val bitmap = BitmapFactory.decodeFile(original.absolutePath) ?: continue
                    val compressed = saveCache(bitmap).absolutePath
                    images.put(JSONObject().put("original", original.absolutePath).put("compressed", compressed))
                }
            }
            if (images.length() == 0) error(cb, -1002, "No image selected")
            else result(cb, JSONObject().put("data", images))
        } catch (_: Exception) { error(cb, -1002, "Cannot read selected image") }
    }

    fun openFile(arg: Any, cb: CompletionHandler<Any>) {
        val value = params(arg)?.optString("url").orEmpty()
        val uri = Uri.parse(value)
        val launchUri = when (uri.scheme) {
            "https" -> uri
            "file", null -> trustedFile(value)?.let { FileProvider.getUriForFile(activity, "${activity.packageName}.mwb.files", it) }
            else -> null
        } ?: return error(cb, -1001, "Invalid file URL")
        activity.runOnUiThread {
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(launchUri, "application/pdf")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                result(cb)
            } catch (_: Exception) { error(cb, -1004, "PDF viewer unavailable") }
        }
    }

    fun convertImagePathToBase64(arg: Any, cb: CompletionHandler<Any>) {
        val file = trustedFile(params(arg)?.optString("path")) ?: return error(cb, -1001, "Invalid image path")
        result(cb, JSONObject().put("base64Image", Base64.encodeToString(file.readBytes(), Base64.NO_WRAP)))
    }

}
