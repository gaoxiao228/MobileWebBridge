package com.mobilewebbridge

import org.json.JSONObject

/** 原生异步回调共用 errCode 结构。 */
object MWBResult {
    fun success(value: Any? = null): JSONObject = JSONObject().put("errCode", 0).also {
        if (value != null) it.put("result", value)
    }
    fun failure(code: Int, message: String): JSONObject = JSONObject()
        .put("errCode", code).put("errorMsg", message)
}
