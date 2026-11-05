import Foundation

/// 新插件传输在 JavaScript 实际执行时再次核对文档，避免 DSBridge 的延迟缓存跨页。
enum MWBPluginJavaScript {
    static func reply(callback: String, document: String, result: MWBResult) -> String? {
        guard callback.range(of: "^dscb[0-9]+$", options: .regularExpression) != nil else { return nil }
        let values: [Any] = [document, callback, result.jsonString]
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return """
        (()=>{const [doc,key,result]=\(json);
          if(window.__mwbNativePluginDocumentId!==doc)return;
          const callback=window[key];delete window[key];
          if(typeof callback==='function')callback(result);
        })();
        """
    }
    static func event(_ message: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return "" }
        // DSBridge 的同步 register 就存放在 _dsf；事件没有原生回执，也不缓存历史消息。
        return """
        (()=>{const message=\(json);
          if(window.__mwbNativePluginDocumentId!==message.documentId)return;
          const callback=window._dsf&&window._dsf['mwb.pluginEvent'];
          if(typeof callback==='function')callback(message);
        })();
        """
    }
}
