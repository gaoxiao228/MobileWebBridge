package com.mobilewebbridge

import android.graphics.Color
import java.io.Serializable
import org.json.JSONObject

/** 可配置的原生返回展示，wire 值与 JS 公共契约一致。 */
enum class MWBBackButtonStyle(val wire: String) { TEXT("text"), ARROW("arrow"), ARROW_TEXT("arrowText") }
/** 系统字体标题字重。 */
enum class MWBTitleFontWeight(val wire: String, val weight: Int) {
    REGULAR("regular", 400), MEDIUM("medium", 500), SEMIBOLD("semibold", 600), BOLD("bold", 700)
}

/** 宿主默认外观只存值，不包含页面标题、显隐、操作或回调。 */
data class MWBNavigationBarAppearance(
    val color: Int? = null, val titleColor: Int? = null, val buttonColor: Int? = null,
    val backButtonStyle: MWBBackButtonStyle? = null, val backButtonText: String? = null,
    val separatorVisible: Boolean? = null, val separatorColor: Int? = null,
    val titleFontSize: Float? = null, val titleFontWeight: MWBTitleFontWeight? = null,
    val buttonFontSize: Float? = null
) : Serializable {
    init {
        require(titleFontSize == null || (titleFontSize.isFinite() && titleFontSize > 0 && titleFontSize <= 32))
        require(buttonFontSize == null || (buttonFontSize.isFinite() && buttonFontSize > 0 && buttonFontSize <= 28))
        require(backButtonText == null || backButtonText.isNotBlank())
    }

    /** 保留未传字段；显式按钮色始终独立于后续标题色。 */
    internal fun merge(patch: MWBNavigationBarAppearance) = MWBNavigationBarAppearance(
        patch.color ?: color, patch.titleColor ?: titleColor, patch.buttonColor ?: buttonColor,
        patch.backButtonStyle ?: backButtonStyle, patch.backButtonText ?: backButtonText,
        patch.separatorVisible ?: separatorVisible, patch.separatorColor ?: separatorColor,
        patch.titleFontSize ?: titleFontSize, patch.titleFontWeight ?: titleFontWeight, patch.buttonFontSize ?: buttonFontSize)
}

/** 解析完成才允许修改控件或启动 Activity；Intent 只携带已验证的值。 */
internal data class MWBNavigationBarPatch(val appearance: MWBNavigationBarAppearance, val showBackButton: Boolean?) : Serializable {
    companion object {
        val keys = setOf("color", "titleColor", "buttonColor", "backButtonStyle", "backButtonText", "showBackButton",
            "separatorVisible", "separatorColor", "titleFontSize", "titleFontWeight", "buttonFontSize")

        fun parse(params: JSONObject, strict: Boolean = false): MWBNavigationBarPatch {
            fun text(key: String): String? = if (!params.has(key)) null else
                (params.opt(key) as? String ?: throw IllegalArgumentException("$key must be a string"))
            fun boolean(key: String): Boolean? = if (!params.has(key)) null else
                (params.opt(key) as? Boolean ?: throw IllegalArgumentException("$key must be boolean"))
            fun color(key: String): Int? {
                if (!params.has(key)) return null
                val value = text(key)!!
                if (strict || key !in setOf("color", "titleColor")) require(Regex("#?[0-9a-fA-F]{6}").matches(value))
                return Color.parseColor("#${value.removePrefix("#")}")
            }
            fun size(key: String, max: Float): Float? {
                if (!params.has(key)) return null
                val number = params.opt(key) as? Number ?: throw IllegalArgumentException("$key must be a number")
                val value = number.toFloat()
                require(value.isFinite() && value > 0 && value <= max)
                return value
            }
            val style = text("backButtonStyle")?.let { value -> MWBBackButtonStyle.entries.firstOrNull { it.wire == value }
                ?: throw IllegalArgumentException("Invalid backButtonStyle") }
            val weight = text("titleFontWeight")?.let { value -> MWBTitleFontWeight.entries.firstOrNull { it.wire == value }
                ?: throw IllegalArgumentException("Invalid titleFontWeight") }
            val label = text("backButtonText")
            require(label == null || label.isNotBlank())
            return MWBNavigationBarPatch(MWBNavigationBarAppearance(color("color"), color("titleColor"), color("buttonColor"),
                style, label, boolean("separatorVisible"), color("separatorColor"), size("titleFontSize", 32f),
                weight, size("buttonFontSize", 28f)), boolean("showBackButton"))
        }
    }
}
