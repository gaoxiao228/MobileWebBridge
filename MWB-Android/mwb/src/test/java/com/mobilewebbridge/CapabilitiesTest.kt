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
    @Test fun navigateAppearanceOverridesHostPerFieldBeforeFirstPageLoad() {
        // 打开只覆盖标题色时，宿主的独立按钮色仍保留，且不需要目标 JS。
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet(),
            navigationBarAppearance = MWBNavigationBarAppearance(
                titleColor = android.graphics.Color.BLACK, buttonColor = android.graphics.Color.GREEN,
                backButtonStyle = MWBBackButtonStyle.TEXT, titleFontSize = 18f))
        val source = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
        NavigationApi(source).navigateTo(JSONObject().put("url", config.initialUrl).put("hidden", false)
            .put("title", "打开覆盖").put("titleColor", "ffffff"), object : CompletionHandler<Any> {
            override fun complete(retValue: Any) { assertEquals(0, (retValue as JSONObject).getInt("errCode")) }
            override fun complete() = Unit
            override fun setProgressData(value: Any) = Unit
        })
        val target = Robolectric.buildActivity(MWBActivity::class.java,
            org.robolectric.Shadows.shadowOf(source).nextStartedActivity).setup().get()
        val views = descendants(target.navigationBar!!)
        val title = views.filterIsInstance<TextView>().single { it.text == "打开覆盖" }
        val back = views.filterIsInstance<Button>().single { it.text == "返回" }
        assertEquals(android.graphics.Color.WHITE, title.currentTextColor)
        assertEquals(android.graphics.Color.GREEN, back.currentTextColor)
        assertEquals(View.VISIBLE, back.visibility)
        assertEquals(View.VISIBLE, target.navigationBar!!.visibility)
    }

    @Test fun actionIsRemovedOnDocumentInvalidationAndExtDoesNotLeak() {
        val activity = activity()
        val view = activity.webView!!
        val client = org.robolectric.Shadows.shadowOf(view).webViewClient
        client.onPageStarted(view, "file:///android_asset/index.html", null)
        assertTrue(activity.applyNavigationTheme(JSONObject().put("actionTxt", "保存").put("actionExt", "old")))
        val oldDocument = activity.pluginSession.replyDocumentId()
        activity.reload()
        val action = descendants(activity.navigationBar!!).filterIsInstance<Button>().single { it.text.isEmpty() && it.visibility == View.GONE }
        assertEquals(View.GONE, action.visibility)
        client.onPageStarted(view, "file:///android_asset/index.html", null)
        assertNotEquals(oldDocument, activity.pluginSession.replyDocumentId())
        assertTrue(activity.applyNavigationTheme(JSONObject().put("actionTxt", "新操作")))
        action.performClick()
        val queue = wendu.dsbridge.DWebView::class.java.getDeclaredField("callInfoList").apply { isAccessible = true }.get(view) as List<*>
        val call = queue.last()!!
        val data = call.javaClass.getDeclaredField("data").apply { isAccessible = true }.get(call)
        assertFalse(data.toString().contains("old"))
    }

    @Test fun longBackTextAndActionDoNotOverlapOnNarrowScreen() {
        val activity = activity()
        assertTrue(activity.applyNavigationTheme(JSONObject().put("backButtonStyle", "arrowText")
            .put("backButtonText", "返回上一个非常长的页面名称").put("buttonFontSize", 28)
            .put("actionTxt", "保存").put("showCloseButton", true)))
        val bar = activity.navigationBar!!
        bar.layoutDirection = View.LAYOUT_DIRECTION_LTR
        val scale = activity.resources.displayMetrics.density
        val width = (320 * scale).toInt()
        // Robolectric 的 CJK 字体测量偏小，用原生最小宽度模拟实际长文本的固有宽度。
        descendants(bar).filterIsInstance<Button>().single { it.text.startsWith("返回上一个") }.minimumWidth = width
        bar.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        bar.layout(0, 0, width, bar.measuredHeight)
        val back = descendants(bar).filterIsInstance<Button>().single { it.text.startsWith("返回上一个") }
        val action = descendants(bar).filterIsInstance<Button>().single { it.text == "关闭" }
        val backRect = android.graphics.Rect(); val actionRect = android.graphics.Rect()
        back.getDrawingRect(backRect); action.getDrawingRect(actionRect)
        (bar as ViewGroup).offsetDescendantRectToMyCoords(back, backRect)
        bar.offsetDescendantRectToMyCoords(action, actionRect)
        assertTrue("返回控件必须实际布局: $backRect", backRect.width() > 0 && backRect.height() > 0)
        assertTrue("关闭控件必须实际布局: $actionRect", actionRect.width() > 0 && actionRect.height() > 0)
        assertTrue("返回 $backRect 与关闭 $actionRect 不可交叠", backRect.right <= actionRect.left)
        assertTrue("长返回须为另一侧按钮预留宽度", back.width <= width / 2)
    }

    @Test fun explicitArrowAndTextArrowUseRtlAndNativeTouchTargets() {
        val activity = activity()
        val bar = activity.navigationBar!!
        bar.layoutDirection = View.LAYOUT_DIRECTION_RTL
        assertTrue(activity.applyNavigationTheme(JSONObject().put("backButtonStyle", "arrow")))
        val arrow = descendants(bar).filterIsInstance<ImageButton>().single()
        assertTrue(arrow.drawable.isAutoMirrored)
        assertTrue(activity.applyNavigationTheme(JSONObject().put("backButtonStyle", "arrowText")
            .put("backButtonText", "返回上一页").put("buttonFontSize", 28).put("titleFontSize", 32)))
        val back = descendants(bar).filterIsInstance<Button>().single { it.text == "返回上一页" }
        assertTrue(back.compoundDrawablesRelative[0].isAutoMirrored)
        assertEquals(View.VISIBLE, back.visibility)
        val width = (360 * activity.resources.displayMetrics.density).toInt()
        bar.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        bar.layout(0, 0, width, bar.measuredHeight)
        assertTrue(back.width >= 48 * activity.resources.displayMetrics.density)
        assertTrue(back.height >= 48 * activity.resources.displayMetrics.density)
    }

    @Test fun independentButtonColorSurvivesTitleAndNewAction() {
        // 标题改变和添加按钮不能重置显式按钮色。
        val activity = activity()
        assertTrue(activity.applyNavigationTheme(JSONObject().put("titleColor", "0b4148").put("buttonColor", "049f91")))
        assertTrue(activity.applyNavigationTheme(JSONObject().put("titleColor", "ffffff").put("actionTxt", "保存")))
        val action = descendants(activity.navigationBar!!).filterIsInstance<Button>().single { it.text == "保存" }
        assertEquals(android.graphics.Color.rgb(4, 159, 145), action.currentTextColor)
        val back = descendants(activity.navigationBar!!).filterIsInstance<ImageButton>().single()
        assertEquals(android.graphics.Color.rgb(4, 159, 145), back.imageTintList!!.defaultColor)
    }

    @Test fun invalidAppearanceIsAtomicAndDoesNotLaunchReplacement() {
        val activity = activity()
        activity.title = "原页"
        assertFalse(activity.applyNavigationTheme(JSONObject().put("title", "错误").put("buttonColor", "bad")))
        assertEquals("原页", activity.title)
        assertEquals(-1001, redirect(activity, JSONObject().put("url", "file:///android_asset/index.html").put("titleFontSize", 100)))
        assertNull(org.robolectric.Shadows.shadowOf(activity).nextStartedActivity)
        assertFalse(activity.isFinishing)
    }

    @Test fun redirectCarriesInitialAppearanceAndDoesNotRequireTargetJavaScript() {
        // 目标创建完即可读到外观，不调用 setNavigationBarTheme 补设。
        val source = activity()
        assertEquals(0, redirect(source, JSONObject().put("url", "file:///android_asset/index.html")
            .put("hidden", false).put("title", "初始外观").put("titleColor", "0b4148").put("buttonColor", "049f91")
            .put("backButtonStyle", "arrowText").put("backButtonText", "返回").put("showBackButton", false)
            .put("separatorVisible", true).put("separatorColor", "dfe8e5").put("titleFontSize", 17)
            .put("titleFontWeight", "semibold").put("buttonFontSize", 16)))
        val target = Robolectric.buildActivity(MWBActivity::class.java,
            org.robolectric.Shadows.shadowOf(source).nextStartedActivity).setup().get()
        val title = descendants(target.navigationBar!!).filterIsInstance<TextView>().single { it.text == "初始外观" }
        assertEquals(android.graphics.Color.rgb(11, 65, 72), title.currentTextColor)
        assertEquals(17f * target.resources.displayMetrics.scaledDensity, title.textSize, 0.01f)
        val back = descendants(target.navigationBar!!).filterIsInstance<ImageButton>().single()
        assertEquals(View.GONE, back.visibility)
    }

    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private fun activity(): MWBActivity {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        return Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
    }

    /** 通过与 DSBridge 相同的反射入口执行，漏注册时先给出明确断言。 */
    private fun redirect(activity: MWBActivity, params: JSONObject): Int {
        var code = Int.MIN_VALUE
        val entry = MWBBridgeAdapter::class.java.methods.firstOrNull { it.name == "redirectTo" }
        assertNotNull("redirectTo must be exposed to DSBridge", entry)
        entry!!.invoke(MWBBridgeAdapter(activity), params, object : CompletionHandler<Any> {
            override fun complete(retValue: Any) { code = (retValue as JSONObject).getInt("errCode") }
            override fun complete() = Unit
            override fun setProgressData(value: Any) = Unit
        })
        return code
    }

    @Test fun redirectToReplacesOnlyCurrentActivityAndInitializesNewNavigation() {
        // Robolectric 复用沙箱；只在测试中隔离前例遗留的弱引用注册表。
        val containers = MWBActivity::class.java.getDeclaredField("containers").apply { isAccessible = true }
        (containers.get(null) as MutableList<*>).clear()
        // 打开 B 后 A 必须结束，P 保持；新页使用自己的标题和导航栏参数。
        val previous = activity()
        val source = activity()
        assertEquals(0, redirect(source, JSONObject().put("url", "file:///android_asset/index.html")
            .put("title", "B").put("hidden", false)))
        assertTrue(source.isFinishing)
        assertFalse(previous.isFinishing)
        val launched = org.robolectric.Shadows.shadowOf(source).nextStartedActivity
        assertNotNull(launched)
        val child = Robolectric.buildActivity(MWBActivity::class.java, launched).setup().get()
        assertEquals("B", child.title.toString())
        assertEquals(View.VISIBLE, child.navigationBar?.visibility)
        assertNotSame(source.webView, child.webView)
        // 返回根也不能把被替换的 A 当成存活根。
        MWBActivity.finishToRoot(child)
        assertTrue(child.isFinishing)
        assertFalse(previous.isFinishing)
    }

    @Test fun redirectToDefaultsToHiddenAndRejectsDuplicateLaunches() {
        val source = activity()
        val params = JSONObject().put("url", "file:///android_asset/index.html")
        assertEquals(0, redirect(source, params))
        assertEquals(-1004, redirect(source, params))
        var navigateCode = 0
        NavigationApi(source).navigateTo(params, object : CompletionHandler<Any> {
            override fun complete(retValue: Any) { navigateCode = (retValue as JSONObject).getInt("errCode") }
            override fun complete() = Unit
            override fun setProgressData(value: Any) = Unit
        })
        assertEquals(-1004, navigateCode)
        val shadow = org.robolectric.Shadows.shadowOf(source)
        val child = Robolectric.buildActivity(MWBActivity::class.java, shadow.nextStartedActivity).setup().get()
        assertEquals(View.GONE, child.navigationBar?.visibility)
        assertNull(shadow.nextStartedActivity)
    }

    @Test fun redirectedRootBecomesTheNewRootForLaterChildren() {
        // 使用独立的容器注册表验证根替换，避免前例 Activity 干扰根页选择。
        val containers = MWBActivity::class.java.getDeclaredField("containers").apply { isAccessible = true }
        (containers.get(null) as MutableList<*>).clear()
        val source = activity()
        assertEquals(0, redirect(source, JSONObject().put("url", "file:///android_asset/index.html")))
        val target = org.robolectric.Shadows.shadowOf(source).nextStartedActivity
        val newRoot = Robolectric.buildActivity(MWBActivity::class.java, target).setup().get()
        val child = activity()
        MWBActivity.finishToRoot(child)
        assertTrue(source.isFinishing)
        assertFalse(newRoot.isFinishing)
        assertTrue(child.isFinishing)
    }

    @Test fun redirectToRejectsSourceThatAlreadyOpenedAnotherPage() {
        // startActivity 到 onPause 之间也不能接受替换，否则 B 会返回刚打开的 C。
        val source = activity()
        val params = JSONObject().put("url", "file:///android_asset/index.html")
        var code = Int.MIN_VALUE
        MWBBridgeAdapter(source).navigateTo(params, object : CompletionHandler<Any> {
            override fun complete(retValue: Any) { code = (retValue as JSONObject).getInt("errCode") }
            override fun complete() = Unit
            override fun setProgressData(value: Any) = Unit
        })
        assertEquals(0, code)
        val shadow = org.robolectric.Shadows.shadowOf(source)
        assertNotNull(shadow.nextStartedActivity)
        assertEquals(-1004, redirect(source, params))
        assertFalse(source.isFinishing)
        assertNull(shadow.nextStartedActivity)
    }

    @Test fun redirectToRejectsPausedSourceAndAllowsItAfterReturning() {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val controller = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup()
        val source = controller.get()
        val params = JSONObject().put("url", "file:///android_asset/index.html")
        // 隐藏页的迟到回调不能替换；真正回到来源页后可重新发起。
        controller.pause()
        assertEquals(-1004, redirect(source, params))
        assertFalse(source.isFinishing)
        assertNull(org.robolectric.Shadows.shadowOf(source).nextStartedActivity)
        controller.resume()
        assertEquals(0, redirect(source, params))
    }

    @Test fun redirectToAllowsSourceAfterNavigatedChildReturns() {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val controller = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup()
        val source = controller.get()
        val params = JSONObject().put("url", "file:///android_asset/index.html")
        MWBBridgeAdapter(source).navigateTo(params, object : CompletionHandler<Any> {
            override fun complete(retValue: Any) = Unit
            override fun complete() = Unit
            override fun setProgressData(value: Any) = Unit
        })
        val launched = org.robolectric.Shadows.shadowOf(source).nextStartedActivity
        val child = Robolectric.buildActivity(MWBActivity::class.java, launched).setup()
        controller.pause().stop()
        child.pause().stop().destroy()
        // 导航互斥只持续到来源页恢复，不能永久禁用它的替换能力。
        controller.start().resume()
        assertEquals(0, redirect(source, params))
    }

    @Test fun redirectToRejectsUnsupportedOptionsAndInvalidFieldsWithoutClosingSource() {
        // false 同样属于尚未支持的字段；不能悄悄忽略等待参数。
        for (value in listOf(true, false, JSONObject.NULL)) {
            val source = activity()
            assertEquals(-1004, redirect(source, JSONObject().put("url", "file:///android_asset/index.html")
                .put("waitForReady", value)))
            assertFalse(source.isFinishing)
            assertNull(org.robolectric.Shadows.shadowOf(source).nextStartedActivity)
        }
        for (params in listOf(JSONObject(), JSONObject().put("url", "https://untrusted.example/"),
            JSONObject().put("url", "file:///android_asset/index.html").put("hidden", 1),
            JSONObject().put("url", "file:///android_asset/index.html").put("title", true))) {
            val source = activity()
            assertEquals(-1001, redirect(source, params))
            assertFalse(source.isFinishing)
            assertNull(org.robolectric.Shadows.shadowOf(source).nextStartedActivity)
        }
    }

    @Test fun redirectToRejectsUntrustedSourceBeforeNavigation() {
        val source = activity()
        val view = source.webView!!
        org.robolectric.Shadows.shadowOf(view).webViewClient.onPageStarted(view, "https://untrusted.example/", null)
        assertEquals(-1006, redirect(source, JSONObject().put("url", "file:///android_asset/index.html")))
        assertFalse(source.isFinishing)
        assertNull(org.robolectric.Shadows.shadowOf(source).nextStartedActivity)
    }

    /** 只替代系统启动边界，用真实桥接处理启动失败和保留原页。 */
    class FailingRedirectActivity : MWBActivity() {
        override fun startActivity(intent: android.content.Intent) {
            throw android.content.ActivityNotFoundException("test launch failure")
        }
    }

    @Test fun redirectToKeepsSourceWhenActivityLaunchFails() {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val source = Robolectric.buildActivity(FailingRedirectActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup().get()
        assertEquals(-1002, redirect(source, JSONObject().put("url", "file:///android_asset/index.html")))
        assertFalse(source.isFinishing)
        assertNotNull(source.webView)
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
        // 点击和 JavaScript 真正执行之间也可能整页导航，待分发脚本必须绑定文档。
        assertEquals(true, call.javaClass.getDeclaredField("documentBound").apply { isAccessible = true }.get(call))
        assertEquals(activity.pluginSession.replyDocumentId(), call.javaClass.getDeclaredField("documentId").apply { isAccessible = true }.get(call))

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
