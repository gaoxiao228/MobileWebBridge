package com.mobilewebbridge.capabilities

import android.content.Context
import com.mobilewebbridge.MWBActivity
import com.mobilewebbridge.MWBResult
import org.json.JSONObject

/** 使用分组前缀隔离同步持久化值；有效期由读取时清理。 */
class StorageApi(activity: MWBActivity) {
    private val preferences = activity.getSharedPreferences("mwb.storage", Context.MODE_PRIVATE)

    private fun prefix(group: String?): String {
        val name = group ?: ""
        return "${name.length}:$name:"
    }
    private fun key(name: String, group: String?): String = prefix(group) + name

    fun set(arg: Any): Any {
        val params = arg as? JSONObject ?: return MWBResult.failure(-1001, "Invalid storage parameters")
        val name = params.optString("key")
        if (name.isBlank() || !params.has("data")) return MWBResult.failure(-1001, "Invalid storage parameters")
        val record = JSONObject().put("value", params.opt("data"))
        if (params.has("validSecond")) {
            val seconds = params.optLong("validSecond", -1)
            if (seconds < 0) return MWBResult.failure(-1001, "Invalid expiration")
            record.put("expiresAt", System.currentTimeMillis() + seconds * 1000)
        }
        preferences.edit().putString(key(name, params.optString("groupName", "")), record.toString()).apply()
        return JSONObject.NULL
    }

    fun get(arg: Any): Any {
        val params = arg as? JSONObject ?: return JSONObject()
        val name = params.optString("key")
        if (name.isBlank()) return JSONObject()
        val storageKey = key(name, params.optString("groupName", ""))
        val record = preferences.getString(storageKey, null)?.let { runCatching { JSONObject(it) }.getOrNull() }
            ?: return JSONObject()
        if (record.has("expiresAt") && System.currentTimeMillis() >= record.optLong("expiresAt")) {
            preferences.edit().remove(storageKey).apply()
            return JSONObject()
        }
        return JSONObject().put("data", record.opt("value"))
    }

    fun remove(arg: Any): Any {
        val params = arg as? JSONObject ?: return MWBResult.failure(-1001, "Invalid storage key")
        val name = params.optString("key")
        if (name.isBlank()) return MWBResult.failure(-1001, "Invalid storage key")
        preferences.edit().remove(key(name, params.optString("groupName", ""))).apply()
        return JSONObject.NULL
    }

    fun clear(arg: Any): Any {
        val group = (arg as? JSONObject)?.optString("groupName", "") ?: ""
        val prefix = prefix(group)
        val editor = preferences.edit()
        preferences.all.keys.filter { it.startsWith(prefix) }.forEach(editor::remove)
        editor.apply()
        return JSONObject.NULL
    }
}
