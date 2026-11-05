package com.mobilewebbridge.sample

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** 网络策略在原生控制，网页不能将示例用作任意代理。 */
@RunWith(RobolectricTestRunner::class)
@org.robolectric.annotation.Config(application = android.app.Application::class)
class NetworkServiceTest {
    private class Connection(private val bytes: ByteArray, private val status: Int = 201) : java.net.HttpURLConnection(java.net.URL("https://example.com/")) {
        var disconnected = false
        override fun connect() { }
        override fun disconnect() { disconnected = true }
        override fun usingProxy() = false
        override fun getResponseCode() = status
        override fun getInputStream(): java.io.InputStream = java.io.ByteArrayInputStream(bytes)
        override fun getErrorStream(): java.io.InputStream = java.io.ByteArrayInputStream(bytes)
        override fun getContentLengthLong() = -1L
        override fun getHeaderFields(): Map<String, List<String>> = mapOf("X-Test" to listOf("one", "two"))
        override fun getContentType() = "text/plain; charset=UTF-8"
    }
    @Test fun hostServiceReturnsHttpEnvelopeAndLimitsUnknownLengthBodies() {
        for ((bytes, expectedSuccess) in listOf("created".toByteArray() to true, ByteArray(1024 * 1024 + 1) to false)) {
            val connection = Connection(bytes)
            val service = HostNetworkService(setOf("example.com")) { connection }
            val done = java.util.concurrent.CountDownLatch(1)
            var result: Result<NetworkResponse>? = null
            service.request(NetworkRequest("https://example.com/", "GET", emptyMap(), null)) { result = it; done.countDown() }
            assertTrue(done.await(3, java.util.concurrent.TimeUnit.SECONDS))
            assertEquals(expectedSuccess, result!!.isSuccess)
            assertTrue(connection.disconnected)
            assertFalse(connection.instanceFollowRedirects)
            if (expectedSuccess) {
                assertEquals(201, result!!.getOrThrow().status)
                assertEquals("created", result!!.getOrThrow().body)
                assertEquals("one, two", result!!.getOrThrow().headers["X-Test"])
            }
        }
    }
    @Test fun onlyHttpsAllowlistedGetOrPostRequestsAreAccepted() {
        val service = HostNetworkService(setOf("example.com", "httpbin.org"))
        for (url in listOf("not a URL", "http://example.com/", "https://127.0.0.1/", "https://example.com.evil.org/", "https://user@example.com/", "https://example.com:444/")) {
            assertThrows(IllegalArgumentException::class.java) { service.validate(NetworkRequest(url, "GET", emptyMap(), null)) }
        }
        service.validate(NetworkRequest("https://example.com/", "GET", emptyMap(), null))
        assertThrows(IllegalArgumentException::class.java) { service.validate(NetworkRequest("https://example.com/", "PUT", emptyMap(), null)) }
        assertThrows(IllegalArgumentException::class.java) { NetworkRequest.parse(JSONObject().put("url", "https://example.com/").put("method", "POST").put("headers", JSONObject().put("X-Test", 2))) }
    }
}
