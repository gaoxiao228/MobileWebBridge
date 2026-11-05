package com.mobilewebbridge

import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/** 验证真实容器导航生命周期与插件文档身份的集成。 */
@RunWith(RobolectricTestRunner::class)
class PluginContainerTest {
    @Test fun initialRedirectGetsANewDocumentIdentity() {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val controller = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup()
        val activity = controller.get(); val view = activity.webView!!
        val first = activity.pluginSession.session().getJSONObject("result").getString("documentId")
        shadowOf(view).webViewClient.onPageStarted(view, "file:///android_asset/redirect.html", null)
        assertNotEquals(first, activity.pluginSession.session().getJSONObject("result").getString("documentId"))
        controller.pause().stop().destroy()
    }
    @Test fun firstTrustedScriptCanGetIdentityBeforePageFinishesAndNavigationRevokesIt() {
        val config = MWBConfiguration("file:///android_asset/index.html", emptySet())
        val controller = Robolectric.buildActivity(MWBActivity::class.java,
            MWBActivity.createIntent(ApplicationProvider.getApplicationContext(), config)).setup()
        val activity = controller.get(); val adapter = MWBBridgeAdapter(activity)
        val view = activity.webView!!; val client = shadowOf(view).webViewClient
        val first = (adapter.pluginSession(JSONObject.NULL) as JSONObject).getJSONObject("result").getString("documentId")
        client.onPageStarted(view, "file:///android_asset/index.html", null)
        assertEquals(first, (adapter.pluginSession(JSONObject.NULL) as JSONObject).getJSONObject("result").getString("documentId"))
        client.shouldOverrideUrlLoading(view, "file:///android_asset/index.html#next")
        assertEquals(first, activity.pluginSession.session().getJSONObject("result").getString("documentId"))
        client.onPageStarted(view, "file:///android_asset/next.html", null)
        assertNotEquals(first, activity.pluginSession.session().getJSONObject("result").getString("documentId"))
        activity.reload()
        assertEquals(-1006, activity.pluginSession.session().getInt("errCode"))
        controller.pause().stop().destroy()
        assertTrue(activity.webView == null)
    }
}
