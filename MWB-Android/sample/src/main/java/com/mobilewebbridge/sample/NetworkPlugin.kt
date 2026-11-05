package com.mobilewebbridge.sample

import com.mobilewebbridge.plugins.MWBMethod
import com.mobilewebbridge.plugins.MWBPlugin
import com.mobilewebbridge.plugins.MWBPluginCallContext
import com.mobilewebbridge.plugins.MWBPluginResponder
import org.json.JSONObject

/** 业务插件只编写标记方法；网络策略和线程属于宿主服务。 */
class NetworkPlugin(private val service: NetworkService) : MWBPlugin() {
    @MWBMethod
    fun request(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        val request = runCatching { NetworkRequest.parse(params) }.getOrElse {
            responder.failure(-1102, "Invalid network request"); return
        }
        val cancel = try {
            service.request(request) { result ->
                result.fold(onSuccess = { response ->
                    responder.success(JSONObject().put("status", response.status)
                        .put("headers", JSONObject(response.headers)).put("body", response.body))
                    context.emit("requestFinished", JSONObject().put("url", request.url).put("status", response.status))
                }, onFailure = {
                    // 不将宿主内部异常或凭据写回网页。
                    responder.failure(1001, "Network request failed")
                })
            }
        } catch (_: IllegalArgumentException) {
            responder.failure(-1102, "Network request is not allowed"); return
        }
        context.onCancel(cancel)
    }
}

/** 仅接受 HTTPS 文本请求，字段由两端示例共同约定。 */
data class NetworkRequest(val url: String, val method: String, val headers: Map<String, String>, val body: String?) {
    companion object {
        fun parse(value: Any?): NetworkRequest {
            val obj = value as? JSONObject ?: throw IllegalArgumentException("Expected object")
            val url = obj.opt("url") as? String ?: throw IllegalArgumentException("Expected URL")
            val method = obj.opt("method") as? String ?: throw IllegalArgumentException("Expected method")
            require(method == "GET" || method == "POST")
            val rawHeaders = if (!obj.has("headers")) JSONObject() else obj.opt("headers") as? JSONObject
                ?: throw IllegalArgumentException("Expected string headers")
            val headers = rawHeaders.keys().asSequence().associateWith { key ->
                rawHeaders.opt(key) as? String ?: throw IllegalArgumentException("Expected string header")
            }
            val body = if (!obj.has("body")) null else obj.opt("body") as? String
                ?: throw IllegalArgumentException("Expected string body")
            require(method != "GET" || body == null) { "GET body is not supported" }
            return NetworkRequest(url, method, headers, body)
        }
    }
}

data class NetworkResponse(val status: Int, val headers: Map<String, String>, val body: String)

/** 接入方可替换为已有的签名、登录态或网络连接池服务。 */
interface NetworkService {
    fun request(request: NetworkRequest, completion: (Result<NetworkResponse>) -> Unit): () -> Unit
}
