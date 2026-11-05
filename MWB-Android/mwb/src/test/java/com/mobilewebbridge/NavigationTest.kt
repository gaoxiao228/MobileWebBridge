package com.mobilewebbridge

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** 可信来源规则必须精确匹配协议、主机和端口。 */
@RunWith(RobolectricTestRunner::class)
class NavigationTest {
    private val policy = MWBNavigationPolicy(setOf("https://app.example.test"))

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
