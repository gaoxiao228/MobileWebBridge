package com.mobilewebbridge.plugins

import org.json.JSONArray
import org.json.JSONObject
import java.util.IdentityHashMap

/** 复制合法 JSON，拒绝原生对象、非有限数字和循环，防止跨线程修改发送中的载荷。 */
internal object PluginJson {
    fun copy(value: Any?): Any = copy(value, IdentityHashMap(), 0)
    private fun copy(value: Any?, seen: IdentityHashMap<Any, Boolean>, depth: Int): Any {
        require(depth <= 128) { "JSON nesting is too deep" }
        if (value == null || value === JSONObject.NULL) return JSONObject.NULL
        when (value) {
            is String, is Boolean, is Byte, is Short, is Int, is Long -> return value
            is Float -> { require(value.isFinite()); return value }
            is Double -> { require(value.isFinite()); return value }
        }
        require(seen.put(value, true) == null) { "Cyclic JSON" }
        try {
            return when (value) {
                is JSONObject -> JSONObject().also { out -> value.keys().forEach { key -> out.put(key, copy(value.get(key), seen, depth + 1)) } }
                is JSONArray -> JSONArray().also { out -> for (i in 0 until value.length()) out.put(copy(value.get(i), seen, depth + 1)) }
                is Map<*, *> -> JSONObject().also { out -> value.forEach { (key, item) ->
                    require(key is String); out.put(key, copy(item, seen, depth + 1)) } }
                is List<*> -> JSONArray().also { out -> value.forEach { out.put(copy(it, seen, depth + 1)) } }
                else -> throw IllegalArgumentException("Only JSON values are supported")
            }
        } finally { seen.remove(value) }
    }
}
