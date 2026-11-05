package com.mobilewebbridge

/** 进程级宿主扩展入口，应在 Application 启动时安装。 */
object MWB {
    internal val pluginRegistry = com.mobilewebbridge.plugins.MWBPluginRegistry()

    /** 必须在第一个容器创建前注册；工厂闭包用于注入宿主共享服务。 */
    fun registerPlugin(name: String, factory: () -> com.mobilewebbridge.plugins.MWBPlugin) =
        pluginRegistry.register(name, factory)

    @Volatile var host: MWBHost? = null
        private set

    fun install(host: MWBHost) { this.host = host }
}
