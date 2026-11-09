package com.mobilewebbridge

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.graphics.Color
import android.content.res.ColorStateList
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.webkit.WebResourceError
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import wendu.dsbridge.DWebView
import wendu.dsbridge.OnReturnValue
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

/** 宿主可读取页面加载状态，展示自己的进度或错误界面。 */
enum class MWBLoadState { IDLE, LOADING, LOADED, FAILED }

/** 可由任何宿主 Activity 启动的 MWB Web 容器。 */
open class MWBActivity : Activity() {
    companion object {
        const val EXTRA_CONFIGURATION = "com.mobilewebbridge.configuration"
        internal const val EXTRA_INITIAL_OVERRIDE = "com.mobilewebbridge.initialOverride"
        internal const val EXTRA_TITLE_OVERRIDE = "com.mobilewebbridge.titleOverride"
        internal const val EXTRA_NAVIGATION_HIDDEN = "com.mobilewebbridge.navigationHidden"
        private val containers = mutableListOf<WeakReference<MWBActivity>>()
        fun createIntent(context: Context, configuration: MWBConfiguration): Intent =
            Intent(context, MWBActivity::class.java).putExtra(EXTRA_CONFIGURATION, configuration)

        // 仅保存弱引用，避免宿主销毁或重建 Activity 后被容器注册表持有。
        internal fun finishToRoot(activity: MWBActivity): Boolean {
            val alive = containers.mapNotNull { it.get() }.filter { !it.isFinishing }
            val root = alive.firstOrNull() ?: return false
            alive.drop(1).forEach { if (it !== root) it.finish() }
            return activity !== root
        }
    }

    lateinit var configuration: MWBConfiguration
        private set
    var webView: DWebView? = null
        private set
    var navigationBar: LinearLayout? = null
        private set
    /** 主线程状态变化回调；子类在 super.onCreate 前设置以接收首次加载。 */
    var onLoadStateChange: ((MWBLoadState) -> Unit)? = null
    /** 当前主文档首次就绪时回调；不重放历史，晚订阅可读取 isPageReady。 */
    var onPageReady: (() -> Unit)? = null
    var isPageReady: Boolean = false
        private set
    /** 最近一次主文档加载错误，新加载开始时清除。 */
    var loadError: String? = null
        private set
    var loadState: MWBLoadState = MWBLoadState.IDLE
        private set(value) {
            if (field == value) return
            field = value
            onLoadStateChange?.invoke(value)
        }
    private var loadingUrl: String? = null
    private var progress: ProgressBar? = null
    /** 首页操作仅调用当前实例的宿主回调。 */
    var onGoHome: ((MWBActivity) -> Unit)? = null
        set(value) { field = value; errorPresenter?.updateHomeAvailability(value != null) }
    var errorPageError: MWBPageLoadError? = null
        private set
    private var errorPresenter: com.mobilewebbridge.errorpage.MWBErrorPagePresenter? = null
    private lateinit var content: FrameLayout
    @Volatile private var loadingMethod: String? = "GET"
    private var retrying = false
    private var savedHistory: Bundle? = null
    private var titleView: TextView? = null
    private var backButton: ImageButton? = null
    private var closeButton: Button? = null
    private var actionButton: Button? = null
    private var navigationActionExt: String? = null
    private lateinit var policy: MWBNavigationPolicy
    @Volatile private var trustedPage = false
    private var bridge: MWBBridgeAdapter? = null
    internal lateinit var pluginSession: com.mobilewebbridge.plugins.MWBPluginSession
        private set
    private var initialPluginNavigation = false
    private var initialPluginUrl: String? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var visibleAtMs: Long? = null
    private var hasBeenVisible = false
    private var hasStartedNavigation = false
    /** 容器级互斥，不同桥接适配器也不能重复替换同一来源页。 */
    internal var isRedirecting = false
    /** 子页启动后到来源重新恢复前，阻止迟到的替换请求插入错误返回路径。 */
    internal var hasPendingPageNavigation = false
    internal var isResumedForNavigation = false
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configuration = intent.getSerializableExtra(EXTRA_CONFIGURATION) as? MWBConfiguration
            ?: run { finish(); return }
        intent.getStringExtra(EXTRA_TITLE_OVERRIDE)?.let { title = it }
        synchronized(containers) { containers.removeAll { it.get() == null }; containers.add(WeakReference(this)) }
        policy = MWBNavigationPolicy(configuration.allowedOrigins)
        // 注册表已冻结，所有子容器得到同一份不可变定义，不共享文档实例。
        val weakActivity = WeakReference(this)
        pluginSession = com.mobilewebbridge.plugins.MWBPluginSession(MWB.pluginRegistry.snapshot(),
            { weakActivity.get()?.isTrustedPage() == true }, { weakActivity.get() }) { message ->
            weakActivity.get()?.webView?.callHandlerForDocument("mwb.pluginEvent", arrayOf(message), message.getString("documentId"))
        }
        pluginSession.notifyPageReady = {
            if (!isTrustedPage() || loadState == MWBLoadState.FAILED || isDestroyed) {
                MWBResult.failure(-1104, "Document is no longer active")
            } else {
                // 先记录后回调，允许宿主同步重入导航；不在回调后覆盖新状态。
                if (!isPageReady) { isPageReady = true; onPageReady?.invoke() }
                MWBResult.success()
            }
        }
        val view = createBusinessWebView()
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = networkChanged()
            override fun onLost(network: Network) = networkChanged()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = networkChanged()
        }
        connectivity.registerDefaultNetworkCallback(networkCallback!!)
        webView = view
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setBackgroundColor(Color.WHITE) }
        val navigationContent = FrameLayout(this)
        val navigationHeight = dp(56)
        val back = ImageButton(this).apply {
            setImageResource(R.drawable.mwb_arrow_back)
            imageTintList = ColorStateList.valueOf(Color.BLACK)
            background = null
            contentDescription = "返回"
            setPadding(dp(12), dp(12), dp(12), dp(12))
            setOnClickListener { onBackPressed() }
        }
        val title = TextView(this).apply {
            text = this@MWBActivity.title
            textSize = 18f
            setTextColor(Color.BLACK)
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        val trailing = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val close = Button(this).apply {
            text = "关闭"
            setAllCaps(false)
            setTextColor(Color.BLACK)
            background = null
            minimumWidth = dp(48)
            setPadding(dp(12), 0, dp(12), 0)
            setOnClickListener { finish() }
            visibility = View.GONE
        }
        val action = Button(this).apply {
            setAllCaps(false)
            setTextColor(Color.BLACK)
            background = null
            minimumWidth = dp(48)
            setPadding(dp(12), 0, dp(12), 0)
            visibility = View.GONE
            setOnClickListener {
                // 按钮事件只发送给当前可信页面，不把 JS 函数作为原生参数保存。
                if (trustedPage) {
                    val payload = navigationActionExt?.let { mapOf("actionExt" to it) } ?: emptyMap<String, String>()
                    callJsHandler("navigationActionClick", arrayOf<Any>(payload))
                }
            }
        }
        // 标题覆盖整条导航栏并按两侧较宽的控件留出对称空间，保证视觉居中。
        navigationContent.addView(title, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        navigationContent.addView(back, FrameLayout.LayoutParams(
            dp(52), ViewGroup.LayoutParams.MATCH_PARENT, Gravity.START))
        trailing.addView(close, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT))
        trailing.addView(action, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT))
        navigationContent.addView(trailing, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.END))
        navigationContent.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val inset = maxOf(back.width, trailing.width) + dp(8)
            if (title.paddingLeft != inset) title.setPadding(inset, 0, inset, 0)
        }
        bar.addView(navigationContent, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, navigationHeight))
        val loading = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { isIndeterminate = true; visibility = View.GONE }
        root.addView(bar)
        root.addView(loading, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 3))
        content = FrameLayout(this)
        content.addView(view, FrameLayout.LayoutParams(-1, -1))
        root.addView(content, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        navigationBar = bar
        backButton = back
        titleView = title
        closeButton = close
        actionButton = action
        progress = loading
        setContentView(root)
        // navigateTo 的新页面可在首帧前决定是否显示导航栏。
        if (intent.hasExtra(EXTRA_NAVIGATION_HIDDEN)) {
            applyNavigationTheme(JSONObject().put("hidden", intent.getBooleanExtra(EXTRA_NAVIGATION_HIDDEN, true)))
        }
        errorPresenter = com.mobilewebbridge.errorpage.MWBErrorPagePresenter(this, content, configuration.errorPage,
            { retryFailedPage() }, { goHomeFromError() })
        MWB.host?.configureContainer(this)
        load(intent.getStringExtra(EXTRA_INITIAL_OVERRIDE) ?: configuration.initialUrl)
    }

    /** 重建时复用全部设置与网关，避免新引擎缺少来源限制。 */
    private fun createBusinessWebView(): DWebView {
        val view = DWebView(this)
        // 保持普通点击与滚动，禁用双指缩放及系统长按选项。
        view.settings.setSupportZoom(false)
        view.settings.builtInZoomControls = false
        view.settings.displayZoomControls = false
        view.setOnLongClickListener { true }
        // 上游 DSBridge 默认允许混合内容；容器再次设置以防依赖更新后回退。
        view.settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        view.settings.allowFileAccess = false
        view.settings.allowContentAccess = false
        view.settings.javaScriptCanOpenWindowsAutomatically = false
        DWebView.setWebContentsDebuggingEnabled(false)
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                if (webView !== view) true
                else if (request.isForMainFrame) {
                    loadingMethod = request.method
                    beforeMainNavigation(view.url, request.url.toString())
                }
                else !policy.isTrusted(request.url.toString())
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = webView !== view || beforeMainNavigation(view.url, url)
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (webView !== view) return WebResourceResponse("text/plain", "UTF-8", java.io.ByteArrayInputStream(ByteArray(0)))
                if (request.isForMainFrame) loadingMethod = request.method
                return if (policy.isTrusted(request.url.toString())) null
                else WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden", emptyMap(),
                    java.io.ByteArrayInputStream(ByteArray(0)))
            }
            override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                if (webView !== view || (loadState == MWBLoadState.FAILED && !retrying)) return
                sendEvent("pageHide")
                // 后续整页导航时，当前容器已经可见，白屏从新导航开始计算。
                if (hasBeenVisible && hasStartedNavigation) visibleAtMs = System.currentTimeMillis()
                hasStartedNavigation = true
                // 主框架开始导航时再次校验来源；重定向和资源仍由上面的策略拦截。
                trustedPage = policy.isTrusted(url)
                // 首个可信页的身份已在 load 前建立；不能让早期脚本获得的身份立即失效。
                if (!initialPluginNavigation || initialPluginUrl != url || !trustedPage) {
                    invalidatePluginDocument()
                    if (trustedPage) pluginSession.beginDocument(url)
                }
                initialPluginNavigation = false
                initialPluginUrl = null
                loadingUrl = url
                loadError = null
                progress?.visibility = if (retrying) View.GONE else View.VISIBLE
                loadState = MWBLoadState.LOADING
            }
            override fun onPageFinished(view: WebView, url: String) {
                // 完成不能重新授权失败页面，也不能覆盖另一目标页面的加载状态。
                if (webView !== view || !isCurrentLoad(url) || loadState == MWBLoadState.FAILED || !trustedPage) return
                progress?.visibility = View.GONE
                errorPresenter?.dismiss(); errorPageError = null; retrying = false
                view.visibility = View.VISIBLE
                savedHistory = Bundle().also { view.saveState(it) }
                sendEvent("pageShow")
                publishVisibleAt()
                loadState = MWBLoadState.LOADED
            }
            override fun onRenderProcessGone(view: WebView, detail: android.webkit.RenderProcessGoneDetail): Boolean {
                if (webView !== view) return true
                // 已失效的引擎不可再调用 saveState/reload；使用最近正常页面的历史快照。
                releaseBusinessWebView()
                failLoad("Web content process terminated", MWBPageLoadError.Kind.rendererTerminated)
                return true
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (webView === view && request.isForMainFrame && isCurrentLoad(request.url.toString())) {
                    val kind = when {
                        request.url.scheme == "file" -> MWBPageLoadError.Kind.localResource
                        error.errorCode == WebViewClient.ERROR_TIMEOUT -> MWBPageLoadError.Kind.timeout
                        else -> MWBPageLoadError.Kind.network
                    }
                    failLoad(error.description.toString(), kind, request.method)
                }
            }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (webView === view && request.isForMainFrame && isCurrentLoad(request.url.toString()) && response.statusCode >= 400) {
                    failLoad("HTTP ${response.statusCode}: ${response.reasonPhrase}", MWBPageLoadError.Kind.http, request.method, response.statusCode)
                }
            }
            override fun onReceivedSslError(view: WebView, handler: android.webkit.SslErrorHandler,
                                            error: android.net.http.SslError) {
                handler.cancel()
                if (webView === view && isCurrentLoad(error.url)) failLoad("TLS error: ${error.primaryError}", MWBPageLoadError.Kind.tls)
            }
        }
        webView = view
        bridge = MWBBridgeAdapter(this)
        view.addJavascriptObject(bridge!!, "mwb")
        return view
    }

    private fun releaseBusinessWebView() {
        val old = webView; webView = null
        bridge?.dispose(); bridge = null
        old?.let {
            (it.parent as? ViewGroup)?.removeView(it)
            it.removeJavascriptObject("mwb"); it.stopLoading(); it.destroy()
        }
    }

    /** 重试使用新引擎隔离同 URL 的迟到回调，历史通过平台快照保留。 */
    private fun replaceBusinessWebView() {
        webView?.let { old -> savedHistory = Bundle().also { old.saveState(it) } }
        releaseBusinessWebView()
        val fresh = createBusinessWebView()
        savedHistory?.let { fresh.restoreState(it) }
        content.addView(fresh, 0, FrameLayout.LayoutParams(-1, -1))
    }

    private fun retryFailedPage() {
        val failure = errorPageError ?: return
        if (retrying || !failure.canRetry || isDestroyed || !isTrusted(failure.url)) return
        retrying = true
        errorPresenter?.setRetrying(true)
        invalidatePluginDocument(); trustedPage = false
        replaceBusinessWebView()
        webView?.visibility = View.INVISIBLE
        initialPluginNavigation = false
        loadingUrl = failure.url; loadingMethod = "GET"; loadError = null
        loadState = MWBLoadState.LOADING
        // 宿主状态回调可以同步导航，不能随后覆盖其新目标。
        if (retrying && errorPageError === failure) webView?.loadUrl(failure.url)
    }

    private fun goHomeFromError() {
        if (errorPageError == null || isDestroyed) return
        val callback = onGoHome ?: return
        if (retrying) {
            retrying = false; trustedPage = false; invalidatePluginDocument()
            // 先作废旧 WebView 的所有回调，再允许宿主重入导航。
            replaceBusinessWebView()
            webView?.visibility = View.INVISIBLE
            errorPresenter?.setRetrying(false)
            loadState = MWBLoadState.FAILED
            if (errorPageError == null) return
        }
        callback(this)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !hasBeenVisible) {
            // 首次获得窗口焦点代表用户开始看到原生容器；后续焦点变化不重置计时。
            hasBeenVisible = true
            visibleAtMs = System.currentTimeMillis()
            publishVisibleAt()
        }
    }

    private fun publishVisibleAt() {
        val startedAt = visibleAtMs ?: return
        val page = webView ?: return
        if (!trustedPage || !policy.isTrusted(page.url)) return
        // 同时在可见和加载完成时注入，兼容两种事件先后顺序。
        page.evaluateJavascript(
            "window.__mwbDemoVisibleAt=$startedAt;window.dispatchEvent(new Event('mwb-visible'));", null)
    }

    fun isTrustedPage(): Boolean = trustedPage
    fun isTrusted(url: String?): Boolean = policy.isTrusted(url)

    /** 只允许装载配置中的可信来源。 */
    fun load(url: String): Boolean {
        if (!policy.isTrusted(url)) {
            // 拒绝跳转时保留仍在显示的可信页面；首次无有效页面才报告失败。
            if (loadState == MWBLoadState.IDLE) {
                loadingUrl = url
                failLoad("Untrusted URL: $url", MWBPageLoadError.Kind.blockedNavigation)
            }
            return false
        }
        if (errorPageError != null) {
            replaceBusinessWebView()
            errorPresenter?.dismiss(); errorPageError = null; retrying = false
        }
        if (webView == null) content.addView(createBusinessWebView(), 0, FrameLayout.LayoutParams(-1, -1))
        webView?.visibility = View.VISIBLE
        loadingMethod = "GET"
        // 新空 WebView 的首个目标已通过来源校验，脚本可能早于 onPageStarted 回调。
        // 仅首次加载提前授权；已有文档跳转仍先撤销授权，避免旧页面继承新目标的权限。
        trustedPage = loadState == MWBLoadState.IDLE
        invalidatePluginDocument()
        initialPluginNavigation = trustedPage
        initialPluginUrl = if (trustedPage) url else null
        if (trustedPage) pluginSession.beginDocument(url)
        loadingUrl = url
        loadError = null
        progress?.visibility = View.VISIBLE
        webView?.loadUrl(url)
        loadState = MWBLoadState.LOADING
        return true
    }

    fun reload() {
        if (errorPageError != null) { retryFailedPage(); return }
        val page = webView ?: return
        trustedPage = false
        invalidatePluginDocument()
        initialPluginNavigation = false
        loadError = null
        progress?.visibility = View.VISIBLE
        page.reload()
        loadState = MWBLoadState.LOADING
    }

    /** 失效时立即撤销就绪资格，与现有插件文档使用相同边界。 */
    private fun invalidatePluginDocument() {
        isPageReady = false
        pluginSession.invalidate()
    }

    private fun isCurrentLoad(url: String?): Boolean = url != null &&
        url.substringBefore('#') == loadingUrl?.substringBefore('#')

    private fun failLoad(message: String, kind: MWBPageLoadError.Kind = MWBPageLoadError.Kind.network,
                         method: String? = loadingMethod, status: Int? = null) {
        trustedPage = false
        invalidatePluginDocument()
        loadError = message
        errorPageError = MWBPageLoadError(kind, loadingUrl.orEmpty(), method, message, status)
        retrying = false
        progress?.visibility = View.GONE
        if (configuration.errorPage.enabled) {
            webView?.visibility = View.INVISIBLE
            errorPresenter?.show(errorPageError!!, onGoHome != null)
        }
        // 内部显示完成后才通知宿主；回调可同步 load，不在其后回写。
        loadState = MWBLoadState.FAILED
    }

    /** 仅主文档导航撤销身份；hash 路由不重建插件，子资源不触碰会话。 */
    private fun beforeMainNavigation(current: String?, target: String): Boolean {
        if (!policy.isTrusted(target)) return true
        if (current?.substringBefore('#') != target.substringBefore('#')) {
            // 立即撤销插件身份，同时保留 basic 既有 pageHide 投递时序。
            invalidatePluginDocument()
            initialPluginNavigation = false
        }
        return false
    }

    /** 主题只接受当前壳实际支持的字段，避免 JS 收到虚假成功。 */
    fun applyNavigationTheme(params: JSONObject): Boolean {
        if (listOf("actionIcon", "translucentStatusBars").any(params::has)) return false
        if (params.has("hidden")) navigationBar?.visibility = if (params.optBoolean("hidden")) View.GONE else View.VISIBLE
        if (params.has("title")) { title = params.optString("title"); titleView?.text = title }
        if (params.has("showBackButton")) backButton?.visibility = if (params.optBoolean("showBackButton")) View.VISIBLE else View.GONE
        if (params.has("showCloseButton")) closeButton?.visibility = if (params.optBoolean("showCloseButton")) View.VISIBLE else View.GONE
        if (params.has("actionTxt")) {
            val text = params.optString("actionTxt")
            actionButton?.text = text
            actionButton?.setTextColor(titleView?.currentTextColor ?: Color.BLACK)
            actionButton?.visibility = if (text.isBlank()) View.GONE else View.VISIBLE
            navigationActionExt = params.optString("actionExt").takeIf { params.has("actionExt") }
        } else if (params.has("actionExt")) navigationActionExt = params.optString("actionExt")
        if (params.has("color")) runCatching { Color.parseColor("#${params.optString("color").removePrefix("#")}") }
            .onSuccess { navigationBar?.setBackgroundColor(it) }.onFailure { return false }
        if (params.has("titleColor")) runCatching { Color.parseColor("#${params.optString("titleColor").removePrefix("#")}") }
            .onSuccess {
                titleView?.setTextColor(it)
                actionButton?.setTextColor(it)
                closeButton?.setTextColor(it)
                backButton?.imageTintList = ColorStateList.valueOf(it)
            }.onFailure { return false }
        if (params.has("isBright")) {
            val flag = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            window.decorView.systemUiVisibility = if (params.optBoolean("isBright"))
                window.decorView.systemUiVisibility or flag else window.decorView.systemUiVisibility and flag.inv()
        }
        return true
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + 0.5f).toInt()

    /** Kotlin 主动调用网页注册的 mwb 句柄。 */
    fun callJsHandler(name: String, args: Array<Any> = emptyArray(), callback: ((Any?) -> Unit)? = null) {
        val view = webView ?: return
        if (callback == null) view.callHandler("mwb.$name", args)
        else view.callHandler("mwb.$name", args, OnReturnValue<Any> { callback(it) })
    }

    fun sendEvent(name: String, data: Any? = null) {
        if (trustedPage) callJsHandler("dispatchEvent", arrayOf(mapOf("name" to name, "data" to data)))
    }

    private fun networkChanged() {
        runOnUiThread {
            if (trustedPage) sendEvent("networkStatusChange", mapOf("networkType" to
                (com.mobilewebbridge.capabilities.DeviceApi(this).networkType().optString("networkType"))))
        }
    }

    override fun onResume() {
        super.onResume()
        // 先释放导航互斥，再通知 H5；返回来源后的 appShow 回调可正常发起替换。
        isResumedForNavigation = true
        hasPendingPageNavigation = false
        if (::configuration.isInitialized) sendEvent("appShow")
    }
    override fun onPause() {
        isResumedForNavigation = false
        sendEvent("appHide")
        super.onPause()
    }

    @Deprecated("Uses the Activity back callback for Android API 24 compatibility")
    override fun onBackPressed() {
        val view = webView ?: return super.onBackPressed()
        val fallback = {
            runOnUiThread {
                if (webView !== view) return@runOnUiThread
                if (view.canGoBack()) {
                    // 错误覆盖不能挡住历史恢复；先撤销失败态，再接收新文档回调。
                    val recovering = errorPageError != null
                    if (recovering) {
                        // 失败实例的同 URL 回调也可能迟到，历史恢复同样使用新引擎。
                        replaceBusinessWebView()
                        errorPresenter?.dismiss(); errorPageError = null; retrying = false
                        loadError = null; trustedPage = false; invalidatePluginDocument()
                        webView?.visibility = View.VISIBLE
                    }
                    webView?.goBack()
                    // 最后通知宿主，使其同步 load/关闭的选择不被随后的 goBack 覆盖。
                    if (recovering) loadState = MWBLoadState.LOADING
                } else finish()
            }
        }
        if (loadState != MWBLoadState.LOADED) { fallback(); return }
        val resolved = AtomicBoolean(false)
        // 网页脚本可能缺失或抛错；超时保证系统返回键始终可以回退。
        Handler(Looper.getMainLooper()).postDelayed({
            if (resolved.compareAndSet(false, true)) fallback()
        }, 500)
        callJsHandler("backBtnPressed", callback = { consumed ->
            if (resolved.compareAndSet(false, true) && consumed != true) fallback()
        })
    }

    override fun onDestroy() {
        onLoadStateChange = null
        onPageReady = null
        onGoHome = null
        errorPresenter?.dispose(); errorPresenter = null
        trustedPage = false
        if (::pluginSession.isInitialized) invalidatePluginDocument()
        bridge?.dispose()
        networkCallback?.let {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it)
        }
        networkCallback = null
        synchronized(containers) { containers.removeAll { it.get() == null || it.get() === this } }
        trustedPage = false
        webView?.removeJavascriptObject("mwb")
        webView?.destroy()
        webView = null
        bridge = null
        navigationBar = null
        progress = null
        titleView = null
        backButton = null
        closeButton = null
        actionButton = null
        navigationActionExt = null
        super.onDestroy()
    }

    @Deprecated("Legacy result bridge for Android API 24 compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        bridge?.onActivityResult(requestCode, resultCode, data)
    }

    @Deprecated("Legacy permission bridge for Android API 24 compatibility")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
