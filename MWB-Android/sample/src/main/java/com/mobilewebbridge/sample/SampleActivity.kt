package com.mobilewebbridge.sample

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import java.util.Locale
import android.widget.Button
import com.mobilewebbridge.MWB
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBConfiguration
import com.mobilewebbridge.MWBHost
import org.json.JSONObject

/** 进程启动时安装宿主能力，避免持有页面 Activity 导致泄漏。 */
class SampleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MWB.install(SampleHost(applicationContext))
        // 服务共享，插件按容器文档惰性创建；白名单由宿主配置而非 H5 指定。
        val networkService = HostNetworkService(setOf("example.com", "httpbin.org"))
        MWB.registerPlugin(name = "network") { NetworkPlugin(networkService) }
    }
}

private class SampleHost(private val context: Context) : MWBHost {
    override fun appInfo(): JSONObject = JSONObject().put("appId", context.packageName)
        .put("appVersionName", "0.1.0").put("appVersionCode", 1).put("environment", 0)
    override fun nativePage(name: String, extInfo: JSONObject?): Intent? =
        if (name == "sample") Intent(context, SampleNativeActivity::class.java) else null
}

/** 示例容器直接作为启动页，与 iOS 示例一样展示内置 H5。 */
class SampleWebActivity : MWBActivity() {
    private var readyCount = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        // 启动入口只接受内置页面配置，丢弃外部 Intent 传来的地址覆盖项。
        intent.replaceExtras(Bundle().apply {
            putSerializable(EXTRA_CONFIGURATION,
                MWBConfiguration("file:///android_asset/index.html", emptySet()))
        })
        // 必须先于 super.onCreate 注册，才能收到首次 loading；不要覆盖 WebViewClient。
        onLoadStateChange = { state ->
            Log.i("MWB-Lifecycle", "loadState=${state.name.lowercase(Locale.ROOT)}, isPageReady=$isPageReady")
        }
        onPageReady = {
            readyCount += 1
            Log.i("MWB-Lifecycle", "pageReady count=$readyCount")
        }
        super.onCreate(savedInstanceState)
        // 首页没有上级容器，隐藏空导航栏；H5 子页沿用默认导航行为。
        applyNavigationTheme(JSONObject().put("hidden", true))
    }
}

/** 仅作为已注册原生路由的可见示例。 */
class SampleNativeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(Button(this).apply { text = "原生示例页，点击返回"; setOnClickListener { finish() } })
    }
}
