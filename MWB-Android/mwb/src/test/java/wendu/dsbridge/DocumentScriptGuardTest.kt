package wendu.dsbridge

import org.junit.Assert.*
import org.junit.Test
import org.mozilla.javascript.Context

/** 执行真实生成脚本，防止导航后旧回调触发并删除新页同名 dscb0。 */
@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner::class)
class DocumentScriptGuardTest {
    @Test fun queuedReplyCannotCallOrDeleteNewDocumentCallback() {
        val cx = Context.enter()
        try {
            cx.optimizationLevel = -1
            val scope = cx.initStandardObjects()
            fun eval(script: String): Any = cx.evaluateString(scope, script, "bridge-test", 1, null)
            eval("var window=this;var current='new';var calls=0;window.dscb0=function(){calls++;};var dsBridge={call:function(){return {errCode:0,result:{documentId:current}};}};")
            eval(DocumentScriptGuard.wrap("dscb0({errCode:0});delete window.dscb0;", "old"))
            assertEquals(0.0, Context.toNumber(eval("calls")), 0.0)
            assertEquals("function", Context.toString(eval("typeof dscb0")))
            eval(DocumentScriptGuard.wrap("dscb0({errCode:0});delete window.dscb0;", "new"))
            assertEquals(1.0, Context.toNumber(eval("calls")), 0.0)
            assertEquals("undefined", Context.toString(eval("typeof dscb0")))
        } finally { Context.exit() }
    }
    @Test fun queuedEventCannotEnterAnotherDocument() {
        val cx = Context.enter()
        try {
            cx.optimizationLevel = -1
            val scope = cx.initStandardObjects()
            fun eval(script: String): Any = cx.evaluateString(scope, script, "event-test", 1, null)
            eval("var window=this;var current='new';var events=0;var _handleMessageFromNative=function(){events++;};var dsBridge={call:function(){return {errCode:0,result:{documentId:current}};}};")
            eval(DocumentScriptGuard.wrap("window._handleMessageFromNative({method:'mwb.pluginEvent'});", "old"))
            assertEquals(0.0, Context.toNumber(eval("events")), 0.0)
            eval(DocumentScriptGuard.wrap("window._handleMessageFromNative({method:'mwb.pluginEvent'});", "new"))
            assertEquals(1.0, Context.toNumber(eval("events")), 0.0)
        } finally { Context.exit() }
    }
}
