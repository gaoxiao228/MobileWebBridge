package com.mobilewebbridge.capabilities

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraState
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.exifinterface.media.ExifInterface
import androidx.lifecycle.LiveData
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors

/** SDK 内部单次扫码页，CameraX 与相册共用随 APK 分发的识别器。 */
internal class MWBScannerActivity : ComponentActivity() {
    companion object {
        private const val ALBUM_URI = "selectedAlbumUri"
        private const val PICKING = "pickingImage"
        private const val MAX_IMAGE_SIDE = 2048

        fun createIntent(context: Context, options: MWBScanOptions) = Intent(context, MWBScannerActivity::class.java)
            .putStringArrayListExtra("scanTypes", ArrayList(options.scanTypes))
            .putExtra("showAlbum", options.showAlbum)
    }

    private lateinit var flow: MWBScanFlow
    private lateinit var previewView: PreviewView
    private var chrome: MWBScannerChrome? = null
    private var scanner: BarcodeScanner? = null
    private var provider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var cameraState: LiveData<CameraState>? = null
    private var starting = false
    private var resumed = false
    private var albumUri: Uri? = null
    private val main by lazy { ContextCompat.getMainExecutor(this) }
    private val images = Executors.newSingleThreadExecutor()

    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startCamera() else complete(flow.fail(-1008, "Camera permission denied"))
    }
    private val picker = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) {
            flow.cancelPick()
            startCamera()
        } else if (flow.beginAlbumDecode()) {
            decodeAlbum(uri)
        }
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val types = intent.getStringArrayListExtra("scanTypes")?.toSet().orEmpty()
        val options = MWBScanOptions(types, intent.getBooleanExtra("showAlbum", false))
        flow = MWBScanFlow(options)
        val formats = options.formats()
        if (formats.isEmpty()) return complete(flow.fail(-1001, "Invalid scan type"))
        scanner = try {
            BarcodeScanning.getClient(BarcodeScannerOptions.Builder()
                .setBarcodeFormats(formats[0], *formats.copyOfRange(1, formats.size)).build())
        } catch (_: RuntimeException) {
            return complete(flow.fail(-1004, "Scanner is unavailable"))
        }
        setUpViews(options.showAlbum)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = cancel()
        })
        // 注册器恢复正在打开的系统选图；重建时只保留当前授权的 URI，不复制图片。
        val savedImage = state?.getString(ALBUM_URI)
        if (savedImage != null && flow.beginPick() && flow.beginAlbumDecode()) decodeAlbum(Uri.parse(savedImage))
        else if (state?.getBoolean(PICKING) == true) flow.beginPick()
        if (state == null && !hasCameraPermission()) permission.launch(Manifest.permission.CAMERA)
    }

    @Suppress("DEPRECATION") // API 24–34 仍需显式设为透明，API 35 起系统托管边到边。
    private fun setUpViews(showAlbum: Boolean) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        if (Build.VERSION.SDK_INT >= 29) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
        val layout = FrameLayout(this).apply { setBackgroundColor(0xff151f20.toInt()) }
        previewView = PreviewView(this)
        layout.addView(previewView, FrameLayout.LayoutParams(-1, -1))
        chrome = MWBScannerChrome(this, showAlbum, ::cancel, ::openAlbum).also {
            layout.addView(it, FrameLayout.LayoutParams(-1, -1))
        }
        setContentView(layout)
    }

    override fun onResume() { super.onResume(); resumed = true; startCamera() }
    override fun onPause() { resumed = false; stopCamera(); super.onPause() }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(PICKING, flow.phase == MWBScanFlow.Phase.PICKING)
        albumUri?.let { outState.putString(ALBUM_URI, it.toString()) }
        super.onSaveInstanceState(outState)
    }

    private fun hasCameraPermission() = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
        PackageManager.PERMISSION_GRANTED

    private fun startCamera() {
        if (!resumed || isFinishing || starting || preview != null || !hasCameraPermission() ||
            flow.phase != MWBScanFlow.Phase.CAMERA) return
        chrome?.setScanning(true)
        val epoch = flow.cameraEpoch
        starting = true
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            if (!flow.acceptsCamera(epoch) || !resumed || isDestroyed || isFinishing) return@addListener
            starting = false
            try {
                val currentProvider = future.get()
                val viewfinder = Preview.Builder().build().apply { setSurfaceProvider(previewView.surfaceProvider) }
                val frames = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                // 主线程仅交接帧及状态；ML Kit 在后台解码。完成回调不受 Activity 生命周期限制，必须释放帧。
                frames.setAnalyzer(main) { frame -> analyze(epoch, frame) }
                provider = currentProvider
                preview = viewfinder
                analysis = frames
                val camera = currentProvider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, viewfinder, frames)
                val state = camera.cameraInfo.cameraState
                cameraState = state
                state.observe(this) { complete(flow.cameraError(epoch, it.error)) }
            } catch (_: Exception) {
                complete(flow.fail(-1004, "Camera is unavailable"))
            }
        }, main)
    }

    @androidx.annotation.OptIn(ExperimentalGetImage::class)
    private fun analyze(epoch: Int, frame: ImageProxy) {
        val engine = scanner
        if (engine == null || !flow.acceptsCamera(epoch)) { frame.close(); return }
        val image = frame.image ?: run { frame.close(); return }
        try {
            engine.process(InputImage.fromMediaImage(image, frame.imageInfo.rotationDegrees)).addOnCompleteListener(main) { task ->
                frame.close()
                if (flow.acceptsCamera(epoch)) {
                    if (task.isSuccessful) complete(flow.cameraResult(epoch, task.result.mapNotNull(MWBScanOptions::candidate)))
                    else complete(flow.fail(-1004, "Scanner is unavailable"))
                }
            }
        } catch (_: RuntimeException) {
            frame.close()
            complete(flow.fail(-1004, "Scanner is unavailable"))
        }
    }

    private fun stopCamera() {
        chrome?.setScanning(false)
        flow.invalidateCamera()
        starting = false
        cameraState?.removeObservers(this)
        cameraState = null
        analysis?.clearAnalyzer()
        provider?.unbind(*listOfNotNull(preview, analysis).toTypedArray())
        preview = null
        analysis = null
        provider = null
    }

    private fun openAlbum() {
        if (!hasCameraPermission() || !flow.beginPick()) return
        stopCamera()
        try {
            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        } catch (_: RuntimeException) {
            complete(flow.fail(-1004, "Image picker is unavailable"))
        }
    }

    private fun decodeAlbum(uri: Uri) {
        albumUri = uri
        images.execute {
            val image = runCatching { readLocalImage(uri) }.getOrNull()
            main.execute {
                val engine = scanner
                if (engine == null || flow.phase != MWBScanFlow.Phase.DECODING) {
                    image?.first?.recycle()
                } else if (image == null) {
                    complete(flow.albumResult(null))
                } else {
                    val (bitmap, rotation) = image
                    try {
                        engine.process(InputImage.fromBitmap(bitmap, rotation)).addOnCompleteListener(main) { task ->
                            bitmap.recycle()
                            complete(flow.albumResult(if (task.isSuccessful) task.result.mapNotNull(MWBScanOptions::candidate) else null))
                        }
                    } catch (_: RuntimeException) {
                        bitmap.recycle()
                        complete(flow.albumResult(null))
                    }
                }
            }
        }
    }

    private fun readLocalImage(uri: Uri): Pair<Bitmap, Int>? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > MAX_IMAGE_SIDE) sample *= 2
        val exif = runCatching { contentResolver.openInputStream(uri)?.use { ExifInterface(it) } }.getOrNull()
        val bitmap = contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        if (exif?.isFlipped != true) return bitmap to (exif?.rotationDegrees ?: 0)
        // EXIF 镜像图先水平翻转，再把旋转角交给解码器；不落盘中间图像。
        val mirrored = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height,
            Matrix().apply { setScale(-1f, 1f) }, true)
        if (mirrored !== bitmap) bitmap.recycle()
        return mirrored to exif.rotationDegrees
    }

    private fun cancel() = complete(flow.fail(-1007, "Cancelled"))

    private fun complete(outcome: MWBScanOutcome?) {
        if (outcome == null) return
        stopCamera()
        albumUri = null
        val data = Intent()
        if (outcome.errorCode == 0) {
            setResult(RESULT_OK, data.putExtra("scanType", outcome.scanType).putExtra("code", outcome.code))
        } else {
            setResult(RESULT_CANCELED, data.putExtra("errCode", outcome.errorCode).putExtra("errorMsg", outcome.message))
        }
        finish()
    }

    override fun onDestroy() {
        flow.fail(-1007, "Cancelled")
        stopCamera()
        scanner?.close()
        scanner = null
        images.shutdownNow()
        super.onDestroy()
    }
}
