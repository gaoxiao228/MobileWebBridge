package com.mobilewebbridge.sample

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.Charset
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Sample 宿主异步服务；创建实例不发起请求，只有用户显式调用才联网。 */
class HostNetworkService internal constructor(
    private val allowedHosts: Set<String>,
    private val connectionFactory: (URL) -> HttpURLConnection
) : NetworkService {
    constructor(allowedHosts: Set<String>) : this(allowedHosts, { it.openConnection() as HttpURLConnection })
    private val executor = Executors.newCachedThreadPool()
    internal fun validate(request: NetworkRequest) {
        val url = runCatching { URL(request.url) }.getOrElse { throw IllegalArgumentException("Invalid URL", it) }
        require(url.protocol == "https" && url.host.lowercase() in allowedHosts && url.userInfo == null &&
            (url.port == -1 || url.port == 443)) { "URL is not allowlisted HTTPS" }
        require(request.method == "GET" || request.method == "POST")
        require(request.method != "GET" || request.body == null)
        require(request.body == null || request.body.toByteArray(Charsets.UTF_8).size <= 1024 * 1024)
        request.headers.forEach { (key, value) ->
            require(key.matches(Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")) && '\r' !in value && '\n' !in value)
            // 主机和连接路由完全由经过校验的 URL 决定。
            require(key.lowercase() !in setOf("host", "connection", "content-length", "transfer-encoding"))
        }
    }
    override fun request(request: NetworkRequest, completion: (Result<NetworkResponse>) -> Unit): () -> Unit {
        validate(request)
        val cancelled = AtomicBoolean(false)
        val connection = AtomicReference<HttpURLConnection?>()
        val future = executor.submit {
            val result = runCatching {
                val conn = connectionFactory(URL(request.url))
                connection.set(conn)
                try {
                    check(!cancelled.get())
                    // 不自动跟随重定向，避免白名单地址跳转到内网或任意第三方。
                    conn.instanceFollowRedirects = false
                    conn.connectTimeout = 15000; conn.readTimeout = 15000
                    conn.requestMethod = request.method
                    request.headers.forEach(conn::setRequestProperty)
                    if (request.body != null) {
                        conn.doOutput = true
                        conn.outputStream.use { it.write(request.body.toByteArray(Charsets.UTF_8)) }
                    }
                    val status = conn.responseCode
                    val headers = conn.headerFields.entries.filter { it.key != null }
                        .associate { it.key to it.value.joinToString(", ") }
                    require(conn.contentLengthLong <= 1024 * 1024) { "Response exceeds 1 MiB" }
                    val output = ByteArrayOutputStream()
                    val stream = if (status >= 400) conn.errorStream else conn.inputStream
                    stream?.use { input ->
                        val buffer = ByteArray(8192)
                        while (true) {
                            check(!cancelled.get())
                            val size = input.read(buffer)
                            if (size == -1) break
                            require(output.size() + size <= 1024 * 1024) { "Response exceeds 1 MiB" }
                            output.write(buffer, 0, size)
                        }
                    }
                    val charsetName = Regex("charset=([^;\\s]+)", RegexOption.IGNORE_CASE)
                        .find(conn.contentType.orEmpty())?.groupValues?.get(1)?.trim('"')
                    val charset = runCatching { Charset.forName(charsetName ?: "UTF-8") }.getOrDefault(Charsets.UTF_8)
                    NetworkResponse(status, headers, output.toByteArray().toString(charset))
                } finally { connection.compareAndSet(conn, null); conn.disconnect() }
            }
            if (!cancelled.get()) completion(result)
        }
        return {
            cancelled.set(true)
            connection.getAndSet(null)?.disconnect()
            future.cancel(true)
            Unit
        }
    }
}
