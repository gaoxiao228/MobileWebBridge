package com.mobilewebbridge

import android.webkit.JavascriptInterface
import com.mobilewebbridge.capabilities.DeviceApi
import com.mobilewebbridge.capabilities.MediaApi
import com.mobilewebbridge.capabilities.NavigationApi
import com.mobilewebbridge.capabilities.StorageApi
import org.json.JSONObject
import wendu.dsbridge.CompletionHandler

/** DSBridge 只反射对象自身声明的方法，因此这里集中声明全部原生方法。 */
class MWBBridgeAdapter(private val activity: MWBActivity) {
    companion object {
        val nativeMethods = setOf(
            "setEnableDebug", "navigateTo", "redirectTo", "navigateBack", "navigateBackToRoot", "setNavigationBarTheme",
            "openExternalBrowser", "cleanWebviewCache", "openAppAuthorizeSetting", "toast", "getAppInfoSync",
            "setBadgeCount", "getDeviceInfoSync", "getClipboardDataSync", "setClipboardData", "makePhoneCall",
            "getNetworkTypeSync", "getNotificationSwitchStatus", "exitApp", "openNativePage", "compressImage",
            "scanCode", "saveImageToPhotosAlbum", "chooseImage", "openFile", "checkRequestCameraPermissions",
            "convertImagePathToBase64", "setStorageSync", "getStorageSync",
            "removeStorageSync", "clearStorageSync"
        )
    }

    private val navigation = NavigationApi(activity)
    private val device = DeviceApi(activity)
    private val media = MediaApi(activity)
    private val storage = StorageApi(activity)

    internal fun dispose() { media.dispose() }

    internal fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) =
        media.onActivityResult(requestCode, resultCode, data)
    internal fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grants: IntArray) =
        media.onRequestPermissionsResult(requestCode, grants)

    private fun sync(action: () -> Any): Any = if (activity.isTrustedPage()) action()
        else MWBResult.failure(-1006, "Untrusted page")

    private fun async(callback: CompletionHandler<Any>, action: () -> Unit) {
        if (!activity.isTrustedPage()) callback.complete(MWBResult.failure(-1006, "Untrusted page"))
        else action()
    }

    private fun done(callback: CompletionHandler<Any>, value: JSONObject = MWBResult.success()) { callback.complete(value) }

    // 自定义插件使用独立网关，保留原 basic 的同步与异步入口。
    @JavascriptInterface fun pluginSession(arg: Any): Any = activity.pluginSession.session()
    @JavascriptInterface fun pluginInfo(arg: Any, cb: CompletionHandler<Any>) {
        val document = activity.pluginSession.replyDocumentId()
        activity.pluginSession.info(arg) { cb.completeForDocument(it, document) }
    }
    @JavascriptInterface fun invokePlugin(arg: Any, cb: CompletionHandler<Any>) {
        val document = activity.pluginSession.replyDocumentId()
        activity.pluginSession.invoke(arg) { cb.completeForDocument(it, document) }
    }

    @JavascriptInterface fun setEnableDebug(arg: Any): Any = sync { navigation.setEnableDebug(arg) }
    @JavascriptInterface fun navigateTo(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.navigateTo(arg, cb) }
    @JavascriptInterface fun redirectTo(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.redirectTo(arg, cb) }
    @JavascriptInterface fun navigateBack(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.navigateBack(cb) }
    @JavascriptInterface fun navigateBackToRoot(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.navigateBackToRoot(cb) }
    @JavascriptInterface fun setNavigationBarTheme(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.setNavigationBarTheme(arg, cb) }
    @JavascriptInterface fun openExternalBrowser(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.openExternalBrowser(arg, cb) }
    @JavascriptInterface fun cleanWebviewCache(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.cleanWebviewCache(cb) }
    @JavascriptInterface fun toast(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.toast(arg, cb) }
    @JavascriptInterface fun exitApp(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.exitApp(cb) }
    @JavascriptInterface fun openNativePage(arg: Any, cb: CompletionHandler<Any>) = async(cb) { navigation.openNativePage(arg, cb) }

    @JavascriptInterface fun getAppInfoSync(arg: Any): Any = sync { MWB.host?.appInfo() ?: MWBResult.failure(-1005, "App info is not configured") }
    @JavascriptInterface fun openAppAuthorizeSetting(arg: Any, cb: CompletionHandler<Any>) = async(cb) { device.openSettings(cb) }
    @JavascriptInterface fun setBadgeCount(arg: Any, cb: CompletionHandler<Any>) = async(cb) { device.setBadgeCount(arg, cb) }
    @JavascriptInterface fun getDeviceInfoSync(arg: Any): Any = sync { device.deviceInfo() }
    @JavascriptInterface fun getClipboardDataSync(arg: Any): Any = sync { device.clipboard() }
    @JavascriptInterface fun setClipboardData(arg: Any, cb: CompletionHandler<Any>) = async(cb) { device.setClipboard(arg, cb) }
    @JavascriptInterface fun makePhoneCall(arg: Any, cb: CompletionHandler<Any>) = async(cb) { device.makePhoneCall(arg, cb) }
    @JavascriptInterface fun getNetworkTypeSync(arg: Any): Any = sync { device.networkType() }
    @JavascriptInterface fun getNotificationSwitchStatus(arg: Any, cb: CompletionHandler<Any>) = async(cb) { device.notificationStatus(cb) }

    @JavascriptInterface fun compressImage(arg: Any, cb: CompletionHandler<Any>) = async(cb) { media.compressImage(arg, cb) }
    @JavascriptInterface fun scanCode(arg: Any, cb: CompletionHandler<Any>) = async(cb) { media.scanCode(arg, cb) }
    @JavascriptInterface fun saveImageToPhotosAlbum(arg: Any, cb: CompletionHandler<Any>) = async(cb) { media.saveImage(arg, cb) }
    @JavascriptInterface fun chooseImage(arg: Any, cb: CompletionHandler<Any>) = async(cb) { media.chooseImage(arg, cb) }
    @JavascriptInterface fun openFile(arg: Any, cb: CompletionHandler<Any>) = async(cb) { media.openFile(arg, cb) }
    @JavascriptInterface fun checkRequestCameraPermissions(arg: Any, cb: CompletionHandler<Any>) = async(cb) { media.checkCameraPermission(cb) }
    @JavascriptInterface fun convertImagePathToBase64(arg: Any, cb: CompletionHandler<Any>) = async(cb) { media.convertImagePathToBase64(arg, cb) }

    @JavascriptInterface fun setStorageSync(arg: Any): Any = sync { storage.set(arg) }
    @JavascriptInterface fun getStorageSync(arg: Any): Any = sync { storage.get(arg) }
    @JavascriptInterface fun removeStorageSync(arg: Any): Any = sync { storage.remove(arg) }
    @JavascriptInterface fun clearStorageSync(arg: Any): Any = sync { storage.clear(arg) }
}
