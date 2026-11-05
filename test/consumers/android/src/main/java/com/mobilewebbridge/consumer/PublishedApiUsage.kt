package com.mobilewebbridge.consumer

import android.app.Activity
import android.os.Bundle
import android.content.Context
import android.content.Intent
import com.mobilewebbridge.MWB
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBConfiguration
import com.mobilewebbridge.MWBHost
import com.mobilewebbridge.MWBLoadState
import com.mobilewebbridge.plugins.MWBMethod
import com.mobilewebbridge.plugins.MWBPlugin
import com.mobilewebbridge.plugins.MWBPluginCallContext
import com.mobilewebbridge.plugins.MWBPluginResponder
import org.json.JSONObject

/** 只验证公开接入代码可以针对 Maven AAR 编译，不执行设备或 WebView 行为。 */
object PublishedApiUsage {
    fun configureHost() {
        // 宿主及插件都必须在首个容器创建前注册。
        MWB.install(ConsumerHost())
        MWB.registerPlugin("consumerEcho") { EchoPlugin() }
    }

    fun containerIntent(context: Context): Intent = MWBActivity.createIntent(
        context,
        MWBConfiguration("https://example.com/start", setOf("https://example.com"))
    )
}

/** Android 容器公开入口是 MWBActivity，宿主可以直接继承并调用其控制方法。 */
class ConsumerActivity : MWBActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 消费工程从 AAR 使用回调，不访问 internal 会话。
        onLoadStateChange = { state -> if (state == MWBLoadState.FAILED) println(loadError) }
        onPageReady = { println(isPageReady) }
        super.onCreate(savedInstanceState)
    }
    fun updateContainer() {
        if (loadState == MWBLoadState.LOADED && isTrustedPage()) {
            applyNavigationTheme(JSONObject().put("title", "消费编译验证"))
            callJsHandler("consumerReady", arrayOf(configuration.initialUrl))
            sendEvent("consumerReady", JSONObject().put("ready", true))
        }
        if (isTrusted("https://example.com/next")) load("https://example.com/next")
        reload()
    }
}

/** 编译覆盖宿主接口和来自 Android 平台的参数、返回值。 */
class ConsumerHost : MWBHost {
    override fun appInfo(): JSONObject = JSONObject().put("name", "consumer")
    override fun deviceId(): String = "consumer-fixture"
    override fun setBadgeCount(count: Int): Boolean = count >= 0
    override fun nativePage(name: String, extInfo: JSONObject?): Intent? = null
    override fun closeContainer(activity: Activity): Boolean {
        activity.finish()
        return true
    }
}

/** 编译覆盖插件注解、公开调用上下文及响应器，不访问 internal 注册表。 */
class EchoPlugin : MWBPlugin() {
    @MWBMethod
    fun echo(params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        context.onCancel { /* 实际宿主可在这里取消异步请求。 */ }
        context.emit("echo", JSONObject().put("pageUrl", context.pageUrl))
        if (context.activity == null) responder.failure(-2000, "Container unavailable")
        else responder.success(params)
    }

    override fun dispose() { /* 实际插件在这里释放文档范围内的资源。 */ }
}
