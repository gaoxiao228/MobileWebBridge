package com.mobilewebbridge.sample

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import java.io.File
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.Button
import com.mobilewebbridge.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** 在真实 WebView 内核验证 HTML 动作及历史恢复，不把 Robolectric 当作浏览器。 */
class ErrorPageInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    private fun <T> main(action: () -> T): T {
        var value: T? = null
        runOnMainSync { value = action() }
        @Suppress("UNCHECKED_CAST") return value as T
    }
    private fun await(description: String, predicate: () -> Boolean) {
        val end = SystemClock.uptimeMillis() + 20000
        while (SystemClock.uptimeMillis() < end) {
            if (main(predicate)) return
            SystemClock.sleep(100)
        }
        error("等待失败：$description")
    }
    private fun all(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList()
    private fun script(view: WebView, source: String): String {
        val latch = CountDownLatch(1); var result = ""
        runOnMainSync { view.evaluateJavascript(source) { result = it; latch.countDown() } }
        check(latch.await(5, TimeUnit.SECONDS)) { "JS 回调超时" }
        return result
    }
    /** 协议 ready 可能早于合成帧，截图前等待内容提交并经过后续绘制帧。 */
    private fun painted(view: WebView) {
        // 首个 Activity 的启动转场可能尚未结束，不能只等 DOM 和 WebView 内部帧。
        await("错误页窗口可见") { view.isShown && view.hasWindowFocus() && view.width > 0 && view.height > 0 }
        val latch = CountDownLatch(1)
        runOnMainSync {
            view.postVisualStateCallback(0, object : WebView.VisualStateCallback() {
                override fun onComplete(requestId: Long) {
                    view.postOnAnimation { view.postOnAnimation { latch.countDown() } }
                }
            })
        }
        check(latch.await(5, TimeUnit.SECONDS)) { "错误页绘制未完成" }
        uiAutomation.waitForIdle(500, 5000)
    }
    /** 截图只写到测试 App 私有目录，便于核对两套模板的实际排版。 */
    private fun screenshot(name: String) {
        uiAutomation.takeScreenshot()?.let { bitmap ->
            File(targetContext.filesDir, name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }
    override fun onStart() {
        var activity: MWBActivity? = null
        try {
            val a = startActivitySync(MWBActivity.createIntent(targetContext,
                MWBConfiguration("file:///android_asset/index.html", emptySet())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MWBActivity
            activity = a
            await("业务首页 loaded") { a.loadState == MWBLoadState.LOADED }
            main { a.load("file:///android_asset/mwb-missing.html") }
            await("错误页 HTML 可用") {
                a.loadState == MWBLoadState.FAILED && all(a.window.decorView).filterIsInstance<WebView>()
                    .any { it !== a.webView && it.visibility == View.VISIBLE }
            }
            val page = main { all(a.window.decorView).filterIsInstance<WebView>().first { it !== a.webView } }
            check(script(page, "window.mwbErrorPage.context.version") == "1")
            check(script(page, "typeof window.mwb") == "\"undefined\"")
            check(script(page, "document.compatMode") == "\"CSS1Compat\"")
            check(script(page, "getComputedStyle(document.querySelector('#retry')).borderRadius") == "\"12px\"")
            painted(page)
            screenshot("error-default.png")
            val old = main { a.webView }
            script(page, "document.querySelector('#retry').click();true")
            await("新引擎重试失败") { a.loadState == MWBLoadState.FAILED && a.webView !== old }
            check(main { a.webView!!.canGoBack() }) { "错误重试丢失业务历史" }
            check(main {
                val history = a.webView!!.copyBackForwardList()
                (0 until history.size).none { history.getItemAtIndex(it).url.contains("mwb-error.invalid") }
            }) { "错误文档进入了业务历史" }
            // 使用真正的 HTML 首页动作恢复当前容器。
            script(page, "document.querySelector('#home').click();true")
            await("首页恢复") { a.loadState == MWBLoadState.LOADED && a.errorPageError == null }
            main { a.load("file:///android_asset/mwb-missing.html") }
            await("再次失败") { a.loadState == MWBLoadState.FAILED }
            main { a.onBackPressed() }
            await("错误态系统返回恢复历史") { a.loadState == MWBLoadState.LOADED && a.errorPageError == null }
            main { a.finish() }
            val custom = startActivitySync(MWBActivity.createIntent(targetContext,
                MWBConfiguration("file:///android_asset/mwb-missing.html", emptySet(),
                    MWBErrorPageConfiguration(assetDirectory = "custom-error"))).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MWBActivity
            activity = custom
            await("自定义 HTML 可用") {
                all(custom.window.decorView).filterIsInstance<WebView>().any { it !== custom.webView && it.visibility == View.VISIBLE }
            }
            val customPage = main { all(custom.window.decorView).filterIsInstance<WebView>().first { it !== custom.webView } }
            check(script(customPage, "document.querySelector('h1').textContent").contains("我们再试一次"))
            check(script(customPage, "document.compatMode") == "\"CSS1Compat\"")
            painted(customPage)
            screenshot("error-custom.png")
            script(customPage, "document.querySelector('.home').click();true")
            await("自定义首页恢复") { custom.loadState == MWBLoadState.LOADED && custom.errorPageError == null }
            main { custom.finish() }
            val fallback = startActivitySync(MWBActivity.createIntent(targetContext,
                MWBConfiguration("file:///android_asset/mwb-missing.html", emptySet(),
                    MWBErrorPageConfiguration(assetDirectory = "missing-error"))).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MWBActivity
            activity = fallback
            await("错误资源缺失后进入原生兜底") {
                fallback.errorPageError != null && all(fallback.window.decorView).filterIsInstance<WebView>().all { it === fallback.webView }
            }
            check(main { all(fallback.window.decorView).filterIsInstance<Button>().any { it.text == "重新加载" && it.isEnabled } })
            screenshot("error-fallback.png")
            main { fallback.finish() }
            await("兜底容器已释放") { fallback.isDestroyed }
            val renderer = startActivitySync(MWBActivity.createIntent(targetContext,
                MWBConfiguration("file:///android_asset/index.html", emptySet())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MWBActivity
            activity = renderer
            await("渲染进程验收首页已加载") { renderer.loadState == MWBLoadState.LOADED }
            val crashed = main { renderer.webView!! }
            // Chromium 提供的测试地址只用于验收，真实触发 onRenderProcessGone，不伪造系统回调。
            main { crashed.loadUrl("chrome://crash") }
            await("真实渲染进程终止后显示错误页") {
                renderer.errorPageError?.kind == MWBPageLoadError.Kind.rendererTerminated && !renderer.isFinishing &&
                    all(renderer.window.decorView).filterIsInstance<WebView>().any { it !== renderer.webView && it.visibility == View.VISIBLE }
            }
            val rendererPage = main { all(renderer.window.decorView).filterIsInstance<WebView>().first { it !== renderer.webView } }
            script(rendererPage, "document.querySelector('#retry').click();true")
            await("渲染进程终止后重新加载恢复") {
                renderer.loadState == MWBLoadState.LOADED && renderer.errorPageError == null && renderer.webView !== crashed
            }
            finish(0, Bundle().apply { putString("stream", "PASS: real WebView default/custom HTML, GET retry, history, back, home, missing-template fallback and renderer crash recovery\n") })
        } catch (failure: Throwable) {
            finish(1, Bundle().apply { putString("stream", failure.stackTraceToString()) })
        } finally { activity?.let { a -> runOnMainSync { a.finish() } } }
    }
}
