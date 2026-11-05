package com.mobilewebbridge.capabilities

import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.mobilewebbridge.MWB
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBResult
import org.json.JSONObject
import wendu.dsbridge.CompletionHandler

/** 设备资料和系统能力使用 Android 公共 API，并对宿主能力缺失返回稳定错误。 */
class DeviceApi(private val activity: MWBActivity) {
    fun openSettings(cb: CompletionHandler<Any>) {
        activity.runOnUiThread {
            try {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${activity.packageName}")))
                cb.complete(MWBResult.success())
            } catch (_: Exception) { cb.complete(MWBResult.failure(-1002, "Cannot open settings")) }
        }
    }

    fun setBadgeCount(arg: Any, cb: CompletionHandler<Any>) {
        val count = (arg as? JSONObject)?.optInt("count", -1) ?: -1
        if (count < 0) return cb.complete(MWBResult.failure(-1001, "Invalid badge count"))
        activity.runOnUiThread {
            cb.complete(if (MWB.host?.setBadgeCount(count) == true) MWBResult.success()
                else MWBResult.failure(-1005, "Badge capability is not configured"))
        }
    }

    fun deviceInfo(): JSONObject {
        val statusId = activity.resources.getIdentifier("status_bar_height", "dimen", "android")
        val statusHeight = if (statusId > 0) activity.resources.getDimensionPixelSize(statusId) else 0
        return JSONObject().put("osType", 1).put("osVersion", Build.VERSION.RELEASE)
            .put("model", Build.MODEL).put("brand", Build.BRAND)
            .put("deviceId", MWB.host?.deviceId() ?: "")
            .put("statusBarHeight", statusHeight).put("bottomSafeAreaHeight", 0)
    }

    fun clipboard(): JSONObject {
        val manager = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        return JSONObject().put("data", manager.primaryClip?.getItemAt(0)?.coerceToText(activity)?.toString() ?: "")
    }

    fun setClipboard(arg: Any, cb: CompletionHandler<Any>) {
        val value = (arg as? JSONObject)?.optString("data", null)
            ?: return cb.complete(MWBResult.failure(-1001, "Clipboard data is required"))
        activity.runOnUiThread {
            val manager = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            manager.setPrimaryClip(ClipData.newPlainText("MWB", value))
            cb.complete(MWBResult.success())
        }
    }

    fun makePhoneCall(arg: Any, cb: CompletionHandler<Any>) {
        val number = (arg as? JSONObject)?.optString("phoneNumber").orEmpty()
        if (!Regex("^[+0-9*#]+$").matches(number))
            return cb.complete(MWBResult.failure(-1001, "Invalid phone number"))
        activity.runOnUiThread {
            try { activity.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))); cb.complete(MWBResult.success()) }
            catch (_: Exception) { cb.complete(MWBResult.failure(-1002, "Cannot open dialer")) }
        }
    }

    fun networkType(): JSONObject {
        val manager = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = manager.getNetworkCapabilities(manager.activeNetwork)
        val type = when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            // ConnectivityManager 不暴露蜂窝代际；避免把 2G/5G 误报为 4G。
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "unknown"
            else -> "unknown"
        }
        return JSONObject().put("networkType", type)
    }

    fun notificationStatus(cb: CompletionHandler<Any>) {
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        cb.complete(MWBResult.success(JSONObject().put("status", manager.areNotificationsEnabled())))
    }
}
