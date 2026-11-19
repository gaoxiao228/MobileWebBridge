package com.mobilewebbridge.capabilities

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.ComposeShader
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.animation.LinearInterpolator
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.mobilewebbridge.R
import kotlin.math.roundToInt

/** 相机预览上方的原生取景界面；取景框只提供视觉引导，不改变识别区域。 */
internal class MWBScannerChrome(context: Context, showAlbum: Boolean, onClose: () -> Unit, onAlbum: () -> Unit) :
    FrameLayout(context) {
    companion object {
        private const val WHITE = 0xfff7faf9.toInt()
        private const val MINT = 0xff73f4c5.toInt()
        private const val CYCLE_MS = 2300L
        private const val REST_PROGRESS = 0.465f

        // 与 iOS 使用相同的安全区比例和留白，横屏空间不足时优先缩小取景框。
        fun viewfinder(safe: RectF, density: Float): RectF {
            val edge = minOf(safe.width() * 0.67f, 320 * density, safe.height() - 202 * density).coerceAtLeast(0f)
            val minTop = safe.top + 58 * density
            val maxTop = (safe.bottom - 144 * density - edge).coerceAtLeast(minTop)
            val top = (safe.top + safe.height() * 0.45f - edge / 2).coerceIn(minTop, maxTop)
            val left = safe.centerX() - edge / 2
            return RectF(left, top, left + edge, top + edge)
        }
    }

    private val density = resources.displayMetrics.density
    private val reticle = RectF()
    private val track = RectF()
    private val shade = Path().apply { fillType = Path.FillType.EVEN_ODD }
    private val cornerClips = Path()
    private val shadePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xb8080f14.toInt() }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val tailPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var progress = REST_PROGRESS
    private var scanning = false
    private var sweep: ValueAnimator? = null

    private val hint = TextView(context).apply {
        text = "将二维码或条形码放入框内"
        gravity = Gravity.CENTER
        setTextColor(0xffe1e9e7.toInt())
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        maxLines = 1
        includeFontPadding = false
    }

    init {
        setWillNotDraw(false)
        val title = TextView(context).apply {
            text = "扫一扫"
            gravity = Gravity.CENTER
            setTextColor(WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            ViewCompat.setAccessibilityHeading(this, true)
        }
        addView(title, LayoutParams(LayoutParams.WRAP_CONTENT, px(44), Gravity.TOP or Gravity.CENTER_HORIZONTAL)
            .apply { topMargin = px(4) })
        val close = ImageButton(context).apply {
            setImageResource(R.drawable.mwb_scan_close)
            scaleType = android.widget.ImageView.ScaleType.CENTER
            background = InsetDrawable(RippleDrawable(ColorStateList.valueOf(0x33f7faf9), disc(), null), px(4))
            setPadding(0, 0, 0, 0)
            contentDescription = "关闭"
            setOnClickListener { onClose() }
        }
        addView(close, LayoutParams(px(44), px(44), Gravity.TOP or Gravity.LEFT)
            .apply { leftMargin = px(13); topMargin = px(4) })
        addView(hint, LayoutParams(LayoutParams.MATCH_PARENT, px(24)))
        if (showAlbum) {
            val album = Button(context).apply {
                text = "相册"
                contentDescription = "相册"
                setTextColor(WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                isAllCaps = false
                gravity = Gravity.CENTER
                includeFontPadding = false
                stateListAnimator = null
                background = RippleDrawable(ColorStateList.valueOf(0x22f7faf9), null, GradientDrawable().apply {
                    cornerRadius = px(12).toFloat()
                    setColor(WHITE)
                })
                setPadding(0, 0, 0, 0)
                val icon = context.getDrawable(R.drawable.mwb_scan_album)!!.mutate()
                val badge = LayerDrawable(arrayOf(disc(stroke = true), InsetDrawable(icon, px(13))))
                    .apply { setBounds(0, 0, px(48), px(48)) }
                setCompoundDrawables(null, badge, null, null)
                compoundDrawablePadding = px(6)
                setOnClickListener { onAlbum() }
            }
            addView(album, LayoutParams(px(76), px(73), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL)
                .apply { bottomMargin = px(24) })
        }
        ViewCompat.setOnApplyWindowInsetsListener(this) { _, insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            setPadding(safe.left, safe.top, safe.right, safe.bottom)
            insets
        }
    }

    private fun px(value: Int) = (value * density).roundToInt()

    private fun disc(stroke: Boolean = false) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(0x19f1fffc)
        if (stroke) setStroke(px(1), 0x30f1fffc)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val frame = viewfinder(RectF(paddingLeft.toFloat(), paddingTop.toFloat(),
            (width - paddingRight).toFloat(), (height - paddingBottom).toFloat()), density)
        val hintTop = (frame.bottom + px(17)).roundToInt()
        hint.layout(paddingLeft + px(8), hintTop, width - paddingRight - px(8), hintTop + hint.measuredHeight)
        updateReticle(frame)
    }

    private fun updateReticle(frame: RectF) {
        reticle.set(frame)
        shade.rewind()
        shade.addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
        cornerClips.rewind()
        track.setEmpty()
        if (frame.isEmpty) return
        val radius = 14 * density
        shade.addRoundRect(frame, radius, radius, Path.Direction.CW)
        val size = minOf(24 * density, frame.width() / 2)
        for (x in floatArrayOf(frame.left, frame.right - size)) {
            for (y in floatArrayOf(frame.top, frame.bottom - size)) {
                cornerClips.addRect(x - density, y - density, x + size + density, y + size + density, Path.Direction.CW)
            }
        }
        track.set(frame)
        track.inset(5 * density, 5 * density)
        if (track.isEmpty) return
        // 缓存渐变；每帧只更新扫描位置和透明度。
        linePaint.shader = LinearGradient(track.left, 0f, track.right, 0f,
            intArrayOf(0x0073f4c5, MINT, 0xffd7ffeb.toInt(), MINT, 0x0073f4c5),
            floatArrayOf(0f, 0.14f, 0.5f, 0.86f, 1f), Shader.TileMode.CLAMP)
        val vertical = LinearGradient(0f, -30 * density, 0f, 0f, 0x005fffc2, 0x565fffc2, Shader.TileMode.CLAMP)
        val horizontal = LinearGradient(track.left, 0f, track.right, 0f,
            intArrayOf(0x00000000, 0xff000000.toInt(), 0xff000000.toInt(), 0x00000000),
            floatArrayOf(0.01f, 0.18f, 0.82f, 0.99f), Shader.TileMode.CLAMP)
        tailPaint.shader = ComposeShader(vertical, horizontal, PorterDuff.Mode.DST_IN)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawPath(shade, shadePaint)
        if (reticle.isEmpty) return
        val radius = 14 * density
        borderPaint.color = 0x4deafff5
        borderPaint.strokeWidth = density
        canvas.drawRoundRect(reticle, radius, radius, borderPaint)
        if (!track.isEmpty) {
            val position = (progress / 0.94f).coerceAtMost(1f)
            val y = track.top + track.height() * (0.04f + 0.93f * position)
            val opacity = minOf(progress / 0.09f, (0.94f - progress) / 0.15f, 1f).coerceIn(0f, 1f)
            val alpha = (opacity * 255).roundToInt()
            tailPaint.alpha = alpha
            linePaint.alpha = alpha
            canvas.save()
            canvas.clipRect(track)
            canvas.translate(0f, y)
            canvas.drawRect(track.left, -30 * density, track.right, 0f, tailPaint)
            canvas.drawRect(track.left, -2 * density, track.right, 0f, linePaint)
            canvas.restore()
        }
        canvas.save()
        canvas.clipPath(cornerClips)
        borderPaint.color = MINT
        borderPaint.strokeWidth = 2 * density
        canvas.drawRoundRect(reticle, radius, radius, borderPaint)
        canvas.restore()
    }

    fun setScanning(active: Boolean) {
        scanning = active
        updateSweep()
    }

    private fun updateSweep() {
        val motionEnabled = if (Build.VERSION.SDK_INT >= 26) ValueAnimator.areAnimatorsEnabled()
        else Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
        if (!scanning || !isAttachedToWindow || !motionEnabled) {
            stopSweep()
        } else if (sweep == null) {
            sweep = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = CYCLE_MS
                interpolator = LinearInterpolator()
                repeatCount = ValueAnimator.INFINITE
                addUpdateListener { progress = it.animatedValue as Float; invalidate() }
                start()
            }
        }
    }

    private fun stopSweep() {
        sweep?.cancel()
        sweep = null
        progress = REST_PROGRESS
        invalidate()
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); updateSweep() }
    override fun onDetachedFromWindow() { stopSweep(); super.onDetachedFromWindow() }
}
