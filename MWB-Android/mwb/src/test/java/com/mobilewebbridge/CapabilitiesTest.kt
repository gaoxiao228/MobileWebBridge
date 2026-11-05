package com.mobilewebbridge

import androidx.test.core.app.ApplicationProvider
import com.mobilewebbridge.capabilities.StorageApi
import com.mobilewebbridge.capabilities.MediaApi
import com.mobilewebbridge.capabilities.NavigationApi
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowAlertDialog
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageButton
import android.widget.TextView
import wendu.dsbridge.CompletionHandler

/** 分组隔离和不可信页面拒绝是原生能力的关键边界。 */
@RunWith(RobolectricTestRunner::class)
class CapabilitiesTest {
    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private fun activity(): MWBActivity {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        return Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
    }

    @Test fun storageGroupsAndExpiration() {
        val api = StorageApi(activity())
        api.set(JSONObject().put("key", "token").put("data", "A").put("groupName", "one"))
        api.set(JSONObject().put("key", "token").put("data", "B").put("groupName", "two"))
        assertEquals("A", (api.get(JSONObject().put("key", "token").put("groupName", "one")) as JSONObject).getString("data"))
        api.clear(JSONObject().put("groupName", "one"))
        assertFalse((api.get(JSONObject().put("key", "token").put("groupName", "one")) as JSONObject).has("data"))
        assertEquals("B", (api.get(JSONObject().put("key", "token").put("groupName", "two")) as JSONObject).getString("data"))
        api.set(JSONObject().put("key", "expired").put("data", 1).put("validSecond", 0))
        assertFalse((api.get(JSONObject().put("key", "expired")) as JSONObject).has("data"))
    }

    @Test fun untrustedPageCannotCallNative() {
        val activity = activity()
        // 显式模拟不可信主框架，不能把已配置可信初始地址的新容器当作不可信页面。
        org.robolectric.Shadows.shadowOf(activity.webView!!).webViewClient.onPageStarted(
            activity.webView!!, "https://untrusted.example/", null)
        val adapter = MWBBridgeAdapter(activity)
        assertEquals(-1006, (adapter.getDeviceInfoSync(JSONObject.NULL) as JSONObject).getInt("errCode"))
        var response: JSONObject? = null
        adapter.toast(JSONObject().put("msg", "x"), object : CompletionHandler<Any> {
            override fun complete(retValue: Any) { response = retValue as JSONObject }
            override fun complete() = Unit
            override fun setProgressData(value: Any) = Unit
        })
        assertEquals(-1006, response?.getInt("errCode"))
    }

    @Test fun trustedPageCanCallNativeDuringInitialScripts() {
        val activity = activity()
        // 新 WebView 的可信首个文档可能在主线程收到 onPageStarted 之前执行脚本。
        val result = MWBBridgeAdapter(activity).getDeviceInfoSync(JSONObject.NULL) as JSONObject
        assertEquals(1, result.getInt("osType"))
    }

    @Test fun subsequentNavigationDoesNotAuthorizePreviousUntrustedDocument() {
        val activity = activity()
        val view = activity.webView!!
        val client = org.robolectric.Shadows.shadowOf(view).webViewClient
        client.onPageStarted(view, "https://untrusted.example/", null)
        assertFalse(activity.load("https://untrusted.example/next"))
        assertFalse(activity.isTrustedPage())
        // 只对新空 WebView 的首个可信目标提前授权；已有文档跳转时仍等待主框架回调。
        assertTrue(activity.load("file:///android_asset/index.html?mwbChild=1"))
        val adapter = MWBBridgeAdapter(activity)
        assertEquals(-1006, (adapter.getDeviceInfoSync(JSONObject.NULL) as JSONObject).getInt("errCode"))
        client.onPageStarted(view, "file:///android_asset/index.html?mwbChild=1", null)
        assertEquals(1, (adapter.getDeviceInfoSync(JSONObject.NULL) as JSONObject).getInt("osType"))
    }

    @Test fun allImageSourceOffersAlbumAndCameraChoice() {
        val api = MediaApi(activity())
        val callback = object : CompletionHandler<Any> {
            override fun complete(retValue: Any) = Unit
            override fun complete() = Unit
            override fun setProgressData(value: Any) = Unit
        }
        api.chooseImage(JSONObject().put("sourceType", "all").put("count", 2), callback)
        assertNotNull(ShadowAlertDialog.getLatestAlertDialog())
    }

    @Test fun fireAndForgetEventsDoNotRetainNativeCallbacks() {
        val activity = activity()
        val view = activity.webView!!
        org.robolectric.Shadows.shadowOf(view).webViewClient.onPageStarted(view, "file:///android_asset/index.html", null)
        activity.sendEvent("pageShow")
        val field = wendu.dsbridge.DWebView::class.java.getDeclaredField("handlerMap").apply { isAccessible = true }
        assertEquals(0, (field.get(view) as Map<*, *>).size)
    }

    @Test fun unsupportedNavigateOptionsReturnError() {
        val activity = activity()
        val view = activity.webView!!
        org.robolectric.Shadows.shadowOf(view).webViewClient.onPageStarted(view, "file:///android_asset/index.html", null)
        var code = 0
        MWBBridgeAdapter(activity).navigateTo(JSONObject().put("url", "file:///android_asset/index.html").put("isPopUp", true),
            object : CompletionHandler<Any> {
                override fun complete(retValue: Any) { code = (retValue as JSONObject).getInt("errCode") }
                override fun complete() = Unit
                override fun setProgressData(value: Any) = Unit
            })
        assertEquals(-1004, code)
    }

    @Test fun navigateToHidesNavigationByDefaultAndCanShowItExplicitly() {
        // 新容器默认隐藏原生导航栏；配置页传 hidden=false 时仍能预览导航样式。
        for ((params, expectedVisibility) in listOf(
            JSONObject().put("url", "file:///android_asset/index.html") to View.GONE,
            JSONObject().put("url", "file:///android_asset/index.html").put("hidden", false) to View.VISIBLE
        )) {
            val parent = activity()
            NavigationApi(parent).navigateTo(params, object : CompletionHandler<Any> {
                override fun complete(retValue: Any) = Unit
                override fun complete() = Unit
                override fun setProgressData(value: Any) = Unit
            })
            val launched = org.robolectric.Shadows.shadowOf(parent).nextStartedActivity
            assertNotNull(launched)
            val child = Robolectric.buildActivity(MWBActivity::class.java, launched).setup().get()
            assertEquals(expectedVisibility, child.navigationBar?.visibility)
        }
    }

    @Test fun navigationTextActionShowsButtonAndDispatchesClick() {
        // 文字按钮显示在导航栏右侧，点击时把 actionExt 发送到当前 H5。
        val activity = activity()
        val view = activity.webView!!
        org.robolectric.Shadows.shadowOf(view).webViewClient.onPageStarted(view, "file:///android_asset/index.html", null)
        assertTrue(activity.applyNavigationTheme(JSONObject().put("actionTxt", "保存").put("actionExt", "draft-42")
            .put("color", "112233").put("titleColor", "ffffff")))
        val bar = activity.navigationBar!!
        val action = descendants(bar).filterIsInstance<Button>().single { it.text.toString() == "保存" }
        assertEquals("保存", action.text.toString())
        assertEquals(android.graphics.Color.WHITE, action.currentTextColor)
        action.performClick()
        // Robolectric 不执行网页中的 DSBridge 初始化，检查其真实待分发队列。
        val field = wendu.dsbridge.DWebView::class.java.getDeclaredField("callInfoList").apply { isAccessible = true }
        val call = (field.get(view) as List<*>).last()!!
        val method = call.javaClass.getDeclaredField("method").apply { isAccessible = true }.get(call)
        val data = call.javaClass.getDeclaredField("data").apply { isAccessible = true }.get(call)
        assertEquals("mwb.navigationActionClick", method)
        assertTrue(data.toString().contains("draft-42"))

        assertTrue(activity.applyNavigationTheme(JSONObject().put("actionTxt", "")))
        assertEquals(android.view.View.GONE, action.visibility)
    }

    @Test fun navigationTitleIsCenteredWithTextActionsAndArrowBack() {
        // 同时显示关闭与右侧操作时，标题仍按整个导航栏居中，操作控件不带实心背景。
        val activity = activity()
        assertTrue(activity.applyNavigationTheme(JSONObject().put("title", "导航栏样式")
            .put("actionTxt", "保存").put("showCloseButton", true).put("titleColor", "112233")))
        val bar = activity.navigationBar!!
        val views = descendants(bar)
        val title = views.filterIsInstance<TextView>().single { it.text.toString() == "导航栏样式" }
        val back = views.filterIsInstance<ImageButton>().single { it.contentDescription == "返回" }
        val action = views.filterIsInstance<Button>().single { it.text.toString() == "保存" }
        val close = views.filterIsInstance<Button>().single { it.text.toString() == "关闭" }

        val width = 360
        val height = 64
        bar.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        bar.layout(0, 0, width, height)
        var titleLeft = title.left
        var parent = title.parent as View
        while (parent !== bar) { titleLeft += parent.left; parent = parent.parent as View }
        assertEquals(width / 2, titleLeft + title.width / 2)
        assertEquals(Gravity.CENTER_HORIZONTAL, title.gravity and Gravity.HORIZONTAL_GRAVITY_MASK)
        assertEquals(title.paddingLeft, title.paddingRight)
        assertTrue(title.paddingLeft >= action.width + close.width)
        assertNotNull(back.drawable)
        assertNull(action.background)
        assertNull(close.background)
        assertEquals("保存", action.text.toString())
    }

    @Test fun unsupportedScannerAlbumOptionReturnsError() {
        var code = 0
        MediaApi(activity()).scanCode(JSONObject().put("hideAlbum", false), object : CompletionHandler<Any> {
            override fun complete(retValue: Any) { code = (retValue as JSONObject).getInt("errCode") }
            override fun complete() = Unit
            override fun setProgressData(value: Any) = Unit
        })
        assertEquals(-1004, code)
    }
}
