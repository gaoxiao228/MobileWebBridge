package wendu.dsbridge;

/** 插件脚本的文档执行边界，供回调与事件共同使用。 */
final class DocumentScriptGuard {
    private DocumentScriptGuard() { }
    static String wrap(String script, String documentId) {
        String expected = documentId == null ? "null" : org.json.JSONObject.quote(documentId);
        // 身份来自同步原生网关；不信任页面自存的 documentId 变量。
        return "(function(){try{var s=window.dsBridge.call('mwb.pluginSession');" +
                "var d=s&&s.errCode===0&&s.result?s.result.documentId:null;" +
                "if(d!==" + expected + ")return;}catch(e){return;}" + script + "})();";
    }
}
