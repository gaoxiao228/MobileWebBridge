package com.mobilewebbridge

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** 可信来源规则必须精确匹配协议、主机和端口。 */
@RunWith(RobolectricTestRunner::class)
class NavigationTest {
    private val policy = MWBNavigationPolicy(setOf("https://app.example.test"))

    @Test fun configurationDefaultsToWildcardAndPreservesExplicitRestrictions() {
        // 默认值与调用方显式设置区分，避免把空白名单误当作放开全部来源。
        val url = "https://example.com/app"
        assertEquals(setOf("*"), MWBConfiguration(url).allowedOrigins)
        assertTrue(MWBConfiguration(url, emptySet()).allowedOrigins.isEmpty())
        assertEquals(setOf("https://example.com"), MWBConfiguration(url, setOf("https://example.com")).allowedOrigins)
    }

    @Test fun wildcardTrustsAllHttpOriginsIncludingMixedConfiguration() {
        // 星号既可单独配置，也可与精确来源混合；重定向目标沿用相同规则。
        for (origins in listOf(setOf("*"), setOf("https://app.example.test", "*"))) {
            val wildcard = MWBNavigationPolicy(origins)
            for (url in listOf("https://example.com/app", "http://other.example.test/path",
                "https://other.example.test:8443/redirect")) {
                assertTrue(url, wildcard.isTrusted(url))
            }
        }
    }

    @Test fun wildcardPreservesSchemeAndLocalFileBoundaries() {
        // 放开远程来源不等于允许任意协议或设备文件。
        val wildcard = MWBNavigationPolicy(setOf("*"))
        assertTrue(wildcard.isTrusted("file:///android_asset/index.html"))
        for (url in listOf(null, "", "javascript:alert(1)", "data:text/html,hello", "about:blank",
            "ftp://example.com/a", "https:/missing-host", "file:///sdcard/index.html",
            "file://evil/android_asset/index.html", "file:///android_asset/../outside.html")) {
            assertFalse(url, wildcard.isTrusted(url))
        }
    }

    @Test fun partialWildcardDoesNotTrustSubdomains() {
        // 仅完整星号具有通配语义，空集合仍只允许内置资源。
        assertFalse(MWBNavigationPolicy(setOf("https://*.example.com")).isTrusted("https://app.example.com"))
        assertFalse(MWBNavigationPolicy(emptySet()).isTrusted("https://example.com"))
    }

    @Test fun rejectsUntrustedOriginsAndRedirects() {
        assertTrue(policy.isTrusted("https://app.example.test/path"))
        assertFalse(policy.isTrusted("https://app.example.test.evil.test/"))
        assertFalse(policy.isTrusted("http://app.example.test/"))
        assertFalse(policy.isTrusted("https://app.example.test:444/"))
        assertTrue(MWBNavigationPolicy(setOf("http://localhost:8765")).isTrusted("http://localhost:8765/app"))
        assertFalse(policy.isTrusted("javascript:alert(1)"))
        assertTrue(policy.isTrusted("file:///android_asset/index.html"))
        assertFalse(policy.isTrusted("file:///sdcard/index.html"))
    }
}
