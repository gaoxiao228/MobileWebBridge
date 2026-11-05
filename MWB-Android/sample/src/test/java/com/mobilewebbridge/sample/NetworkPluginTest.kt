package com.mobilewebbridge.sample

import android.app.Application
import android.content.Intent
import android.os.Looper
import com.mobilewebbridge.MWB
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBBridgeAdapter
import com.mobilewebbridge.MWBConfiguration
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import wendu.dsbridge.CompletionHandler

/** 通过真实网关测试注入宿主服务；不依赖外部请求。 */
@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class)
class NetworkPluginTest {
    @Test fun gatewayInjectsServiceAndEmitsScopedFinishedEventAndCancelsOnNavigation() {
        var complete: ((Result<NetworkResponse>) -> Unit)? = null
        var cancelled = false
        var received: NetworkRequest? = null
        val service = object : NetworkService {
            override fun request(request: NetworkRequest, completion: (Result<NetworkResponse>) -> Unit): () -> Unit {
                received = request; complete = completion
                return { cancelled = true }
            }
        }
        MWB.registerPlugin("network") { NetworkPlugin(service) }
        val intent = Intent().putExtra(MWBActivity.EXTRA_CONFIGURATION,
            MWBConfiguration("file:///android_asset/index.html", emptySet()))
        val controller = Robolectric.buildActivity(MWBActivity::class.java, intent).setup()
        val activity = controller.get(); val adapter = MWBBridgeAdapter(activity)
        val session = (adapter.pluginSession(JSONObject.NULL) as JSONObject).getJSONObject("result")
        val arg = JSONObject().put("protocol", 1).put("documentId", session.getString("documentId"))
            .put("plugin", "network").put("method", "request").put("callId", "network-test").put("timeoutMs", 30000)
            .put("params", JSONObject().put("url", "https://example.com/").put("method", "GET"))
        var response: JSONObject? = null
        var replyDocument: String? = null
        val cb = object : CompletionHandler<Any> {
            override fun complete(value: Any?) { response = value as JSONObject }
            override fun completeForDocument(value: Any?, documentId: String?) {
                replyDocument = documentId
                complete(value)
            }
            override fun complete() { fail("Expected response envelope") }
            override fun setProgressData(value: Any?) { fail("Unexpected progress") }
        }
        adapter.invokePlugin(arg, cb)
        assertEquals("GET", received!!.method)
        Thread { complete!!(Result.success(NetworkResponse(200, mapOf("X-Test" to "yes"), "hello"))) }.apply { start(); join() }
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("hello", response!!.getJSONObject("result").getString("body"))
        assertEquals(session.getString("documentId"), replyDocument)
        assertFalse(cancelled)
        adapter.invokePlugin(arg.put("callId", "pending"), cb)
        activity.reload()
        assertTrue(cancelled)
        controller.pause().stop().destroy()
    }
}
