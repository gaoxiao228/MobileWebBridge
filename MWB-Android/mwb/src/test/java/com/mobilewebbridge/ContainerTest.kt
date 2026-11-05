package com.mobilewebbridge

import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import android.os.Looper
import java.time.Duration
import org.robolectric.shadows.ShadowSystemClock

/** 验证配置传递与容器创建的最小集成路径。 */
@RunWith(RobolectricTestRunner::class)
class ContainerTest {
    @Test fun configurationAndIntent() {
        val config = MWBConfiguration("https://app.example.test/start", setOf("https://app.example.test"))
        val intent = MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)
        assertEquals(config, intent.getSerializableExtra(MWBActivity.EXTRA_CONFIGURATION))
        assertThrows(IllegalArgumentException::class.java) { MWBConfiguration("", emptySet()) }
    }

    @Test fun activityCreatesDsbridgeView() {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val activity = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
        assertNotNull(activity.webView)
        assertEquals("file:///android_asset/index.html", activity.webView?.url)
        assertNotNull(activity.navigationBar)
        assertEquals(MWBLoadState.LOADING, activity.loadState)
    }

    @Test fun webViewBlocksPinchZoomAndLongPressMenu() {
        // 容器默认禁止页面缩放与系统长按菜单，普通点击仍交给 WebView。
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val activity = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
        val view = activity.webView!!
        assertFalse(view.settings.supportZoom())
        assertFalse(view.settings.builtInZoomControls)
        // Robolectric 不派发 WebView 真机长按；直接验证注册的监听器会消费事件。
        assertTrue(view.isLongClickable)
        assertEquals(true, Shadows.shadowOf(view).onLongClickListener?.onLongClick(view))
    }

    @Test fun visibleContainerPublishesTimestampToLoadedPage() {
        // 白屏起点要在容器可见后注入给 H5，不能用 onPageFinished 当作起点。
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val activity = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
        val view = activity.webView!!
        activity.onWindowFocusChanged(true)
        Shadows.shadowOf(view).webViewClient.onPageFinished(view, "file:///android_asset/index.html")

        val injected = Shadows.shadowOf(view).lastEvaluatedJavascript.orEmpty()
        assertTrue(injected.contains("__mwbDemoVisibleAt"))
        assertTrue(injected.contains("mwb-visible"))
    }

    @Test fun repeatedNavigationBeforeFinishUsesLatestStart() {
        // 连续跳转时前一页可能尚未完成，最终页面必须使用最近一次导航起点。
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val activity = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
        val view = activity.webView!!
        val client = Shadows.shadowOf(view).webViewClient
        activity.onWindowFocusChanged(true)
        client.onPageStarted(view, "file:///android_asset/index.html", null)
        ShadowSystemClock.advanceBy(Duration.ofMillis(200))
        client.onPageStarted(view, "file:///android_asset/index.html", null)
        ShadowSystemClock.advanceBy(Duration.ofMillis(200))
        val latestStart = System.currentTimeMillis()
        client.onPageStarted(view, "file:///android_asset/index.html", null)
        client.onPageFinished(view, "file:///android_asset/index.html")

        val injected = Shadows.shadowOf(view).lastEvaluatedJavascript.orEmpty()
        val visibleAt = Regex("__mwbDemoVisibleAt=(\\d+)").find(injected)!!.groupValues[1].toLong()
        assertTrue(visibleAt >= latestStart)
    }

    @Test fun backBeforeJavascriptReadyClosesContainer() {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val activity = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
        activity.onBackPressed()
        Shadows.shadowOf(Looper.getMainLooper()).idle()
        assertTrue(activity.isFinishing)
    }
}
