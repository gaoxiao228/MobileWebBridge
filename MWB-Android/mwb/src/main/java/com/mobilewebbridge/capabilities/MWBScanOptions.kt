package com.mobilewebbridge.capabilities

import androidx.camera.core.CameraState
import com.google.mlkit.vision.barcode.common.Barcode
import org.json.JSONObject

/** 桥输入与两种来源共用的码型契约；旧 Android 默认不展示相册。 */
internal data class MWBScanOptions(val scanTypes: Set<String>, val showAlbum: Boolean) {
    companion object {
        private val supported = setOf("qrCode", "barCode")
        private val bars = listOf(Barcode.FORMAT_CODE_128, Barcode.FORMAT_CODE_39, Barcode.FORMAT_CODE_93,
            Barcode.FORMAT_CODABAR, Barcode.FORMAT_EAN_13, Barcode.FORMAT_EAN_8, Barcode.FORMAT_ITF,
            Barcode.FORMAT_UPC_A, Barcode.FORMAT_UPC_E)

        fun parse(params: JSONObject?): MWBScanOptions? {
            val types = if (params?.has("scanType") != true) supported else {
                val values = params.optJSONArray("scanType") ?: return null
                (0 until values.length()).map { values.opt(it) as? String ?: return null }.toSet()
            }
            if (types.isEmpty() || !supported.containsAll(types)) return null
            return MWBScanOptions(types, params?.opt("hideAlbum") == false)
        }

        fun candidate(barcode: Barcode): MWBScanCandidate? = when (barcode.format) {
            Barcode.FORMAT_QR_CODE -> MWBScanCandidate("qrCode", barcode.rawValue)
            in bars -> MWBScanCandidate("barCode", barcode.rawValue)
            else -> null
        }
    }

    fun formats(): IntArray = buildList {
        if ("qrCode" in scanTypes) add(Barcode.FORMAT_QR_CODE)
        if ("barCode" in scanTypes) addAll(bars)
    }.toIntArray()
}

internal data class MWBScanCandidate(val type: String, val text: String?)
internal data class MWBScanOutcome(val scanType: String? = null, val code: String? = null,
    val errorCode: Int = 0, val message: String? = null)

/** 只在主线程推进会话；递增编号让相机异步帧无法穿过选图或前后台切换。 */
internal class MWBScanFlow(private val options: MWBScanOptions) {
    enum class Phase { CAMERA, PICKING, DECODING, FINISHED }
    var phase = Phase.CAMERA
        private set
    var cameraEpoch = 0
        private set

    fun invalidateCamera() { cameraEpoch++ }
    fun acceptsCamera(epoch: Int) = phase == Phase.CAMERA && cameraEpoch == epoch
    fun beginPick(): Boolean {
        if (!options.showAlbum || phase != Phase.CAMERA) return false
        phase = Phase.PICKING
        invalidateCamera()
        return true
    }
    fun cancelPick() { if (phase == Phase.PICKING) phase = Phase.CAMERA }
    fun beginAlbumDecode(): Boolean {
        if (phase != Phase.PICKING) return false
        phase = Phase.DECODING
        return true
    }
    fun cameraResult(epoch: Int, candidates: List<MWBScanCandidate>): MWBScanOutcome? =
        if (acceptsCamera(epoch)) match(candidates)?.let(::finish) else null

    fun cameraError(epoch: Int, error: CameraState.StateError?): MWBScanOutcome? {
        // CameraX 会自行重试可恢复错误；只结算当前绑定的终止性错误。
        if (!acceptsCamera(epoch) || error?.type != CameraState.ErrorType.CRITICAL) return null
        return fail(-1004, "Camera is unavailable")
    }

    fun albumResult(candidates: List<MWBScanCandidate>?): MWBScanOutcome? {
        if (phase != Phase.DECODING) return null
        if (candidates == null) return fail(-1002, "Cannot decode selected image")
        return match(candidates)?.let(::finish) ?: fail(-1004, "No matching code in image")
    }

    fun fail(code: Int, message: String): MWBScanOutcome? = finish(MWBScanOutcome(errorCode = code, message = message))

    private fun match(candidates: List<MWBScanCandidate>): MWBScanOutcome? = candidates
        .firstOrNull { it.type in options.scanTypes && !it.text.isNullOrEmpty() }
        ?.let { MWBScanOutcome(scanType = it.type, code = it.text) }

    private fun finish(outcome: MWBScanOutcome): MWBScanOutcome? {
        if (phase == Phase.FINISHED) return null
        phase = Phase.FINISHED
        invalidateCamera()
        return outcome
    }
}
