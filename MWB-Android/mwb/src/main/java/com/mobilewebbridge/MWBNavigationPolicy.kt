package com.mobilewebbridge

import android.net.Uri

/** 精确比较宿主列出的 HTTP(S) 来源；仅允许打包的 android_asset 文件。 */
class MWBNavigationPolicy(allowedOrigins: Set<String>) {
    private val origins = allowedOrigins.mapNotNull(::origin).toSet()

    fun isTrusted(url: String?): Boolean {
        if (url == null) return false
        val uri = Uri.parse(url)
        if (uri.scheme == "file") return uri.host.isNullOrEmpty() && uri.path?.startsWith("/android_asset/") == true &&
            !uri.pathSegments.contains("..")
        return origin(url)?.let(origins::contains) == true
    }

    private fun origin(value: String): String? {
        val uri = Uri.parse(value)
        if (uri.scheme !in setOf("https", "http") || uri.host.isNullOrBlank() || !uri.userInfo.isNullOrBlank()) return null
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return "${uri.scheme}://${uri.host!!.lowercase()}$port"
    }
}
