import UIKit
import WebKit

/// DSBridge 自行担任 WKUIDelegate；子类补上现代链接长按菜单的禁用回调。
final class MWBInteractionWebView: DWKWebView {
    /// 冷启动和备用实例使用相同固定脚本；业务绑定由真实容器完成。
    static func make() -> MWBInteractionWebView {
        // 每次加载都约束 viewport，并阻止非编辑内容的系统长按选项。
        let interactionScript = WKUserScript(source: """
            (() => {
              let viewport = document.querySelector('meta[name="viewport"]');
              if (!viewport) {
                viewport = document.createElement('meta');
                viewport.name = 'viewport';
                (document.head || document.documentElement).appendChild(viewport);
              }
              const settings = (viewport.content || '').split(',').map(value => value.trim())
                .filter(value => value && !/^(minimum-scale|maximum-scale|user-scalable)\\s*=/.test(value));
              viewport.content = [...settings, 'minimum-scale=1', 'maximum-scale=1', 'user-scalable=no'].join(', ');
              const style = document.createElement('style');
              style.textContent = `html, body { -webkit-touch-callout: none; }
                body { -webkit-user-select: none; user-select: none; }
                input, textarea, [contenteditable], [contenteditable] * {
                  -webkit-user-select: text; user-select: text;
                }`;
              (document.head || document.documentElement).appendChild(style);
              document.addEventListener('contextmenu', event => event.preventDefault(), true);
            })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController.addUserScript(interactionScript)
        // 主文档第一段脚本同步领取原生身份，不等待 didFinish 或业务 SDK 初始化。
        webConfiguration.userContentController.addUserScript(WKUserScript(
            source: "Object.defineProperty(window,'__mwbNativePluginDocumentId',{value:window.prompt('__mwb_plugin_document_start__',''),writable:false,configurable:false});",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        return MWBInteractionWebView(frame: .zero, configuration: webConfiguration)
    }

    weak var pluginController: MWBWebViewController?

    /// DSBridge 的同步 prompt 提供真实 frame；业务网关仅接受主文档。
    override func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                          defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                          completionHandler: @escaping @MainActor (String?) -> Void) {
        if prompt == "__mwb_plugin_document_start__" {
            if frame.isMainFrame, let url = frame.request.url {
                pluginController?.beginPluginDocument(url)
            }
            completionHandler(pluginController?.pluginSession.identity); return
        }
        if ["_dsbridge=mwb.pluginInfo", "_dsbridge=mwb.invokePlugin"].contains(prompt),
           let data = defaultText?.data(using: .utf8),
           let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let callback = envelope["_dscbstub"] as? String,
           let document = pluginController?.pluginSession.identity {
            // 不使用 DSBridge 延迟 jsCache；执行时身份检查保护重用的 dscb 编号。
            pluginController?.pluginBridgeReply = { [weak self] result, _ in
                guard let self, let parsed = MWBResult.parse(result),
                      let script = MWBPluginJavaScript.reply(callback: callback, document: document, result: parsed) else { return }
                self.evaluateJavaScript(script, completionHandler: nil)
            }
        }
        defer { pluginController?.pluginBridgeReply = nil }
        pluginController?.pluginBridgeSource = frame.isMainFrame ? frame.request.url : nil
        defer { pluginController?.pluginBridgeSource = nil }
        super.webView(webView, runJavaScriptTextInputPanelWithPrompt: prompt,
                      defaultText: defaultText, initiatedByFrame: frame, completionHandler: completionHandler)
    }

    override func webView(_ webView: WKWebView, contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo)
        async -> UIContextMenuConfiguration? {
        nil
    }
}
