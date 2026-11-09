package com.mobilewebbridge.capabilities

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.widget.Toast
import com.mobilewebbridge.MWB
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBResult
import org.json.JSONObject
import wendu.dsbridge.CompletionHandler
import wendu.dsbridge.DWebView

/** 导航与容器操作都切到主线程，避免 JS 接口线程触碰视图。 */
class NavigationApi(private val activity: MWBActivity) {
    fun setEnableDebug(arg: Any): Any {
        val requested = (arg as? JSONObject)?.optBoolean("enabled") == true
        val debuggable = activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (requested && !debuggable) return MWBResult.failure(-1004, "Debugging is disabled in release builds")
        DWebView.setWebContentsDebuggingEnabled(requested && debuggable)
        return JSONObject.NULL
    }

    fun toast(arg: Any, cb: CompletionHandler<Any>) {
        val message = (arg as? JSONObject)?.optString("msg").orEmpty()
        if (message.isBlank()) return cb.complete(MWBResult.failure(-1001, "Toast message is required"))
        activity.runOnUiThread { Toast.makeText(activity, message, Toast.LENGTH_SHORT).show(); cb.complete(MWBResult.success()) }
    }

    fun navigateTo(arg: Any, cb: CompletionHandler<Any>) {
        val params = arg as? JSONObject
        val url = params?.optString("url").orEmpty()
        if (!activity.isTrusted(url)) return cb.complete(MWBResult.failure(-1001, "Invalid or untrusted URL"))
        if (params != null && params.keys().asSequence().any { it !in setOf("url", "title", "hidden") })
            return cb.complete(MWBResult.failure(-1004, "Unsupported navigateTo options"))
        activity.runOnUiThread {
            // 已提交替换的旧 Activity 不能再通过 navigateTo 创建另一条页面链。
            if (activity.isRedirecting || activity.isFinishing || activity.isDestroyed)
                return@runOnUiThread cb.complete(MWBResult.failure(-1004, "Current page cannot navigate"))
            // 新容器默认隐藏导航栏；页面可用 hidden=false 显式显示。
            val next = MWBActivity.createIntent(activity, activity.configuration)
                .putExtra(MWBActivity.EXTRA_INITIAL_OVERRIDE, url)
                .putExtra(MWBActivity.EXTRA_NAVIGATION_HIDDEN, params?.optBoolean("hidden", true) ?: true)
            params?.optString("title")?.takeIf(String::isNotEmpty)?.let { next.putExtra(MWBActivity.EXTRA_TITLE_OVERRIDE, it) }
            activity.startActivity(next)
            // 主线程串行记录启动结果，覆盖 startActivity 到 onPause 之间的窗口。
            activity.hasPendingPageNavigation = true
            cb.complete(MWBResult.success())
        }
    }

    fun navigateBack(cb: CompletionHandler<Any>) {
        activity.runOnUiThread {
            cb.complete(MWBResult.success())
            activity.finish()
        }
    }

    /** 新页启动成功才结束来源；等待绘制仍是 iOS 专有能力。 */
    @Suppress("DEPRECATION")
    fun redirectTo(arg: Any, cb: CompletionHandler<Any>) {
        val params = arg as? JSONObject
        val url = params?.opt("url") as? String
        if (url == null || !activity.isTrusted(url))
            return cb.complete(MWBResult.failure(-1001, "Invalid or untrusted URL"))
        if (params.keys().asSequence().any { it !in setOf("url", "title", "hidden") })
            return cb.complete(MWBResult.failure(-1004, "Unsupported redirectTo options"))
        if ((params.has("hidden") && params.opt("hidden") !is Boolean) ||
            (params.has("title") && params.opt("title") !is String))
            return cb.complete(MWBResult.failure(-1001, "Invalid redirectTo field types"))
        val sourceDocument = activity.pluginSession.replyDocumentId()
        activity.runOnUiThread {
            if (activity.isFinishing || activity.isDestroyed || activity.isRedirecting ||
                activity.hasPendingPageNavigation || !activity.isResumedForNavigation)
                return@runOnUiThread cb.complete(MWBResult.failure(-1004, "Current page cannot be replaced"))
            if (!activity.isTrustedPage() || activity.pluginSession.replyDocumentId() != sourceDocument)
                return@runOnUiThread cb.complete(MWBResult.failure(-1005, "Source document is no longer active"))
            val next = MWBActivity.createIntent(activity, activity.configuration)
                .putExtra(MWBActivity.EXTRA_INITIAL_OVERRIDE, url)
                .putExtra(MWBActivity.EXTRA_NAVIGATION_HIDDEN, params.optBoolean("hidden", true))
            if (params.has("title")) next.putExtra(MWBActivity.EXTRA_TITLE_OVERRIDE, params.getString("title"))
            activity.isRedirecting = true
            try {
                activity.startActivity(next)
            } catch (_: ActivityNotFoundException) {
                activity.isRedirecting = false
                return@runOnUiThread cb.complete(MWBResult.failure(-1002, "Cannot start replacement page"))
            } catch (_: SecurityException) {
                activity.isRedirecting = false
                return@runOnUiThread cb.complete(MWBResult.failure(-1002, "Cannot start replacement page"))
            }
            // 与 navigateBack 一样先提交原生回复；旧网页随后销毁，不依赖其继续运行。
            activity.overridePendingTransition(0, 0)
            cb.complete(MWBResult.success())
            activity.finish()
            activity.overridePendingTransition(0, 0)
        }
    }

    fun navigateBackToRoot(cb: CompletionHandler<Any>) {
        activity.runOnUiThread {
            MWBActivity.finishToRoot(activity)
            cb.complete(MWBResult.success())
        }
    }

    fun setNavigationBarTheme(arg: Any, cb: CompletionHandler<Any>) {
        val params = arg as? JSONObject ?: JSONObject()
        activity.runOnUiThread {
            cb.complete(if (activity.applyNavigationTheme(params)) MWBResult.success()
                else MWBResult.failure(-1004, "Unsupported navigation theme"))
        }
    }

    fun openExternalBrowser(arg: Any, cb: CompletionHandler<Any>) {
        val url = (arg as? JSONObject)?.optString("url").orEmpty()
        val uri = Uri.parse(url)
        if (uri.scheme !in setOf("https", "http") || uri.host.isNullOrBlank())
            return cb.complete(MWBResult.failure(-1001, "Invalid external URL"))
        activity.runOnUiThread {
            try { activity.startActivity(Intent(Intent.ACTION_VIEW, uri)); cb.complete(MWBResult.success()) }
            catch (_: ActivityNotFoundException) { cb.complete(MWBResult.failure(-1002, "Cannot open URL")) }
        }
    }

    fun cleanWebviewCache(cb: CompletionHandler<Any>) {
        activity.runOnUiThread { activity.webView?.clearCache(true); cb.complete(MWBResult.success()) }
    }

    fun exitApp(cb: CompletionHandler<Any>) {
        activity.runOnUiThread {
            cb.complete(MWBResult.success())
            if (MWB.host?.closeContainer(activity) != true) activity.finish()
        }
    }

    fun openNativePage(arg: Any, cb: CompletionHandler<Any>) {
        val params = arg as? JSONObject
        val name = params?.optString("pageName").orEmpty()
        if (name.isBlank()) return cb.complete(MWBResult.failure(-1001, "pageName is required"))
        activity.runOnUiThread {
            // 页面 Intent 只能由宿主的显式路由表生成，网页字符串不参与类名解析。
            val intent = MWB.host?.nativePage(name, params?.optJSONObject("extInfo"))
            if (intent == null) cb.complete(MWBResult.failure(-1005, "Native page is not registered"))
            else try { activity.startActivity(intent); cb.complete(MWBResult.success()) }
            catch (_: ActivityNotFoundException) { cb.complete(MWBResult.failure(-1002, "Cannot open native page")) }
        }
    }
}
