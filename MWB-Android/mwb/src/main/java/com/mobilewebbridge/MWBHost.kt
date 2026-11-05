package com.mobilewebbridge

import android.app.Activity
import android.content.Intent
import org.json.JSONObject

/** 应用专属能力由宿主显式实现，页面路由不得由网页传入类名动态解析。 */
interface MWBHost {
    fun appInfo(): JSONObject? = null
    fun deviceId(): String? = null
    fun setBadgeCount(count: Int): Boolean = false
    fun nativePage(name: String, extInfo: JSONObject?): Intent? = null
    fun closeContainer(activity: Activity): Boolean = false
}
