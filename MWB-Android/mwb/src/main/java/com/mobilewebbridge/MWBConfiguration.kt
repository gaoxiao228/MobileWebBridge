package com.mobilewebbridge

import java.io.Serializable

/** 宿主传给 MWBActivity 的启动地址和允许调用原生能力的来源。 */
data class MWBConfiguration(val initialUrl: String, val allowedOrigins: Set<String>) : Serializable {
    init { require(initialUrl.isNotBlank()) { "initialUrl must not be blank" } }
}
