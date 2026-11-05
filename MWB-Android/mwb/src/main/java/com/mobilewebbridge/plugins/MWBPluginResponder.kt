package com.mobilewebbridge.plugins

import com.mobilewebbridge.MWBResult
import org.json.JSONObject

/** 可从任意线程完成；无参数和显式 null 使用不同重载，保持 wire 语义。 */
class MWBPluginResponder internal constructor(private val finish: (JSONObject) -> Unit) {
    fun success() = finish(MWBResult.success())
    fun success(value: Any?) {
        val response = runCatching { MWBResult.success(PluginJson.copy(value)) }
            .getOrElse { MWBResult.failure(-1102, "Plugin result is not JSON") }
        finish(response)
    }
    fun failure(code: Int, message: String) = finish(MWBResult.failure(code, message))
}
