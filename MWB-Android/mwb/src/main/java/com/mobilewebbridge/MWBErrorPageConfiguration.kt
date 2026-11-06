package com.mobilewebbridge

import java.io.Serializable

/** 错误资源仅从 App 的 assets 读取；null 表示 SDK 内置模板。 */
data class MWBErrorPageConfiguration(
    val enabled: Boolean = true,
    val assetDirectory: String? = null,
    val entry: String = "index.html"
) : Serializable

/** 原生诊断信息；URL 和系统 message 不传入错误 HTML。 */
data class MWBPageLoadError(
    val kind: Kind,
    val url: String,
    val method: String?,
    val message: String,
    val httpStatus: Int? = null
) {
    enum class Kind { network, timeout, http, tls, localResource, rendererTerminated, blockedNavigation }
    val canRetry: Boolean get() = method == "GET" && kind != Kind.blockedNavigation
    internal val userMessage: String get() = when (kind) {
        Kind.http -> if (httpStatus == 404) "这个页面暂时找不到了，可以重新加载或返回首页。" else "服务暂时不可用，请稍后重试。"
        Kind.tls -> "无法建立安全连接，请稍后重试。"
        Kind.timeout -> "连接等待时间过长，请重新加载。"
        Kind.blockedNavigation -> "暂时无法打开这个地址，请返回首页。"
        Kind.localResource -> "页面资源暂时无法读取，请重新加载。"
        Kind.rendererTerminated -> "页面意外中断，请重新加载。"
        Kind.network -> "连接暂时不可用，请检查网络后重试。"
    }
}
