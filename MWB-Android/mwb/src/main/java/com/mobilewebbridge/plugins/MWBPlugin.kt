package com.mobilewebbridge.plugins

import java.lang.reflect.Method
import java.lang.reflect.Modifier

/** 只有显式标记且签名合法的实例方法可被网页调用。 */
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class MWBMethod

/** 宿主插件基类；分发不可覆写，清理钩子按活动文档调用。 */
open class MWBPlugin {
    private val methods by lazy {
        val declared = generateSequence(javaClass as Class<*>?) { it.superclass }
            .takeWhile { it != MWBPlugin::class.java }.flatMap { it.declaredMethods.asSequence() }
            .filter { it.isAnnotationPresent(MWBMethod::class.java) }.toList()
        // 同名重载、非法签名不会被反射误调用，而是明确视为插件配置异常。
        require(declared.groupBy { it.name }.all { (_, methods) -> methods.size == 1 }) { "Duplicate plugin method" }
        require(declared.all(::validSignature)) { "Invalid @MWBMethod signature" }
        declared.associateBy { it.name }
    }

    internal fun handle(method: String, params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        val target = methods[method]
        if (target == null) responder.failure(-1101, "Plugin method is not supported")
        else target.invoke(this, params, context, responder)
    }

    private fun validSignature(method: Method): Boolean = PluginNames.method(method.name) &&
        Modifier.isPublic(method.modifiers) && !Modifier.isStatic(method.modifiers) &&
        method.returnType == Void.TYPE && method.parameterTypes.contentEquals(arrayOf(
            Any::class.java, MWBPluginCallContext::class.java, MWBPluginResponder::class.java))

    open fun dispose() { /* 插件可取消自身观察或释放文档范围资源。 */ }
}
