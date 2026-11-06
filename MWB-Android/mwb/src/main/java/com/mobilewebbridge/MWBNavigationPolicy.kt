package com.mobilewebbridge

import android.net.Uri

/** 精确比较 HTTP(S) 来源，单独的 * 允许全部远程来源；本地文件仍限 android_asset。 */
class MWBNavigationPolicy(allowedOrigins: Set<String>) {
    private val allowsAllHttpOrigins = "*" in allowedOrigins
    private val origins = allowedOrigins.mapNotNull(::origin).toSet()

    fun isTrusted(url: String?): Boolean {
        if (url == null) return false
        val uri = Uri.parse(url)
        if (uri.scheme == "file") return uri.host.isNullOrEmpty() && uri.path?.startsWith("/android_asset/") == true &&
            !uri.pathSegments.contains("..")
        // 先校验 HTTP(S) 来源，避免星号放开脚本协议或任意文件。
        return origin(url)?.let { allowsAllHttpOrigins || it in origins } == true
    }

    private fun origin(value: String): String? {
        val uri = Uri.parse(value)
        if (uri.scheme !in setOf("https", "http") || uri.host.isNullOrBlank() || !uri.userInfo.isNullOrBlank()) return null
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return "${uri.scheme}://${uri.host!!.lowercase()}$port"
    }
}
