package com.mobilewebbridge

import java.io.Serializable

/** 默认 setOf("*") 允许所有 HTTP(S) 页面加载并使用原生桥；显式空集合仅允许内置 assets。 */
data class MWBConfiguration(val initialUrl: String, val allowedOrigins: Set<String> = setOf("*"),
    val errorPage: MWBErrorPageConfiguration = MWBErrorPageConfiguration()) : Serializable {
    init { require(initialUrl.isNotBlank()) { "initialUrl must not be blank" } }
}
