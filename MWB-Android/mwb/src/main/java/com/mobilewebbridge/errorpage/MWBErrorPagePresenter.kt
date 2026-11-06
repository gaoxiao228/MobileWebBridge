package com.mobilewebbridge.errorpage

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import android.widget.*
import com.mobilewebbridge.MWBErrorPageConfiguration
import com.mobilewebbridge.MWBPageLoadError
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.util.UUID

/** 普通 WebView 只装载受限错误资源；与 DSBridge 及业务插件完全分离。 */
internal class MWBErrorPagePresenter(
    private val context: Context,
    private val parent: FrameLayout,
    private val configuration: MWBErrorPageConfiguration,
    private val onRetry: () -> Unit,
    private val onGoHome: () -> Unit
) {
    private var overlay: FrameLayout? = null
    private var page: WebView? = null
    private var error: MWBPageLoadError? = null
    private var canGoHome = false
    private var retrying = false
    private var session = ""
    private var entryURL = ""
    private var ready = false
    private var nativeRetry: Button? = null
    private var nativeHome: Button? = null
    private var nativeMessage: TextView? = null
    private val handler = Handler(Looper.getMainLooper())
    private val deadline = Runnable { fallback() }

    fun show(error: MWBPageLoadError, canGoHome: Boolean) {
        this.error = error; this.canGoHome = canGoHome; retrying = false
        if (overlay != null) { update(); return }
        session = UUID.randomUUID().toString()
        // WebView 会规范化 URL；入口包含中文或空格时也必须与回调地址一致。
        entryURL = Uri.Builder().scheme("https").authority("mwb-error.invalid")
            .path("/$session/${configuration.entry}").build().toString()
        val layer = FrameLayout(context).apply { tag = "mwb-error-overlay"; setBackgroundColor(Color.rgb(247, 250, 251)) }
        overlay = layer
        // 原生操作先可用；HTML 超时或引擎不可用时无需再次创建网页。
        val native = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            val padding = (28 * resources.displayMetrics.density).toInt(); setPadding(padding, padding, padding, padding)
        }
        native.addView(TextView(context).apply { text = "页面暂时无法打开"; textSize = 23f; gravity = Gravity.CENTER; setTextColor(Color.rgb(20, 40, 56)) })
        nativeMessage = TextView(context).apply { textSize = 15f; gravity = Gravity.CENTER; setTextColor(Color.rgb(80, 104, 120)) }
        native.addView(nativeMessage)
        nativeRetry = Button(context).apply { setOnClickListener { if (!retrying && this@MWBErrorPagePresenter.error?.canRetry == true) onRetry() } }
        nativeHome = Button(context).apply { text = "回到首页"; setOnClickListener { if (this@MWBErrorPagePresenter.canGoHome) onGoHome() } }
        native.addView(nativeRetry); native.addView(nativeHome)
        layer.addView(native, FrameLayout.LayoutParams(-1, -1))
        parent.addView(layer, FrameLayout.LayoutParams(-1, -1))
        update()
        // 创建 WebView 本身也可能因系统组件损坏失败，原生视图始终保留。
        try {
            val view = WebView(context)
            page = view
            view.visibility = View.INVISIBLE
            view.settings.javaScriptEnabled = true
            view.settings.allowFileAccess = false
            view.settings.allowContentAccess = false
            view.settings.blockNetworkLoads = true
            view.settings.domStorageEnabled = false
            view.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            view.settings.javaScriptCanOpenWindowsAutomatically = false
            view.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest) = response(request)
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val uri = request.url
                    if (page === view && ready && request.isForMainFrame && view.url == entryURL &&
                        uri.scheme == "mwb-error-action" && uri.getQueryParameter("session") == session) {
                        when (uri.host) {
                            "retry" -> if (!retrying && this@MWBErrorPagePresenter.error?.canRetry == true) onRetry()
                            "gohome" -> if (this@MWBErrorPagePresenter.canGoHome) onGoHome()
                        }
                    }
                    return true
                }
                override fun onPageFinished(view: WebView, url: String) {
                    if (page !== view || url != entryURL || view.url != entryURL || ready) return
                    val current = session
                    runCatching {
                        val runtime = context.assets.open("mwb-error/runtime.js").bufferedReader().use { it.readText() }
                        val prefix = JSONObject.quote("mwb-error-action://")
                        val suffix = JSONObject.quote("?session=$session")
                        view.evaluateJavascript("$runtime\nwindow.__mwbInstallErrorPage(${state()},function(action){window.location.href=$prefix+action.toLowerCase()+$suffix;});true;") { result ->
                            if (page !== view || session != current) return@evaluateJavascript
                            if (result == "true") { ready = true; handler.removeCallbacks(deadline); view.visibility = View.VISIBLE }
                            else fallback()
                        }
                    }.onFailure { fallback() }
                }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                    // 缺失/非法本地入口返回 403，不能把空文档注入协议后当作成功模板。
                    if (request.isForMainFrame && response.statusCode >= 400 && page === view) fallback()
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (request.isForMainFrame && page === view) fallback()
                }
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    if (page === view) fallback()
                    return true
                }
            }
            layer.addView(view, FrameLayout.LayoutParams(-1, -1))
            handler.postDelayed(deadline, 5000)
            view.loadUrl(entryURL)
        } catch (_: RuntimeException) { fallback() }
    }

    /** 拦截所有网络请求，只有当前会话路径下的 assets 可以返回内容。 */
    private fun response(request: WebResourceRequest): WebResourceResponse {
        val uri = request.url
        val path = uri.path.orEmpty().removePrefix("/$session/")
        val root = configuration.assetDirectory ?: "mwb-error"
        val allowed = uri.scheme == "https" && uri.host == "mwb-error.invalid" && uri.port == -1 &&
            uri.userInfo == null && uri.path?.startsWith("/$session/") == true && request.method == "GET" &&
            safePath(path) && (root.isEmpty() || safePath(root))
        if (!allowed) return denied()
        return try {
            val bytes = context.assets.open(listOf(root, path).filter { it.isNotEmpty() }.joinToString("/")).use { it.readBytes() }
            val mime = when (path.substringAfterLast('.').lowercase()) {
                "html" -> "text/html"; "css" -> "text/css"; "js" -> "application/javascript"
                "svg" -> "image/svg+xml"; "png" -> "image/png"; "jpg", "jpeg" -> "image/jpeg"
                "webp" -> "image/webp"; "woff" -> "font/woff"; "woff2" -> "font/woff2"; "ttf" -> "font/ttf"
                else -> "application/octet-stream"
            }
            // 本地自定义模板允许内联样式/脚本，但不允许网络、表单、frame 或外部 base。
            val csp = "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
            WebResourceResponse(mime, "UTF-8", 200, "OK", mapOf("Content-Security-Policy" to csp, "Cache-Control" to "no-store"), ByteArrayInputStream(bytes))
        } catch (_: Exception) { denied() }
    }
    private fun safePath(path: String) = path.isNotEmpty() && !path.startsWith('/') &&
        !path.contains('%') && !path.contains('\\') && path.split('/').none { it == "." || it == ".." || it.isEmpty() }
    private fun denied() = WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden", emptyMap(), ByteArrayInputStream(ByteArray(0)))
    private fun state(): JSONObject = JSONObject().put("version", 1).put("kind", error?.kind?.name)
        .put("message", error?.userMessage).put("httpStatus", error?.httpStatus ?: JSONObject.NULL)
        .put("canRetry", error?.canRetry == true).put("canGoHome", canGoHome).put("isRetrying", retrying)
    private fun update() {
        nativeMessage?.text = error?.userMessage
        nativeRetry?.text = if (retrying) "正在重新加载…" else "重新加载"
        nativeRetry?.isEnabled = !retrying && error?.canRetry == true
        nativeHome?.visibility = if (canGoHome) View.VISIBLE else View.GONE
        if (ready) page?.evaluateJavascript("window.__mwbErrorRuntime.update(${state()});", null)
    }
    fun setRetrying(value: Boolean) { retrying = value; update() }
    fun updateHomeAvailability(value: Boolean) { canGoHome = value; update() }
    private fun fallback() {
        handler.removeCallbacks(deadline); ready = false
        val old = page; page = null
        old?.let { (it.parent as? ViewGroup)?.removeView(it); it.destroy() }
    }
    fun dismiss() {
        session = ""; fallback()
        overlay?.let { parent.removeView(it) }; overlay = null
        nativeRetry = null; nativeHome = null; nativeMessage = null; error = null
    }
    fun dispose() = dismiss()
}
