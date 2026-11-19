plugins {
    id("com.android.library") version "8.9.2"
    id("org.jetbrains.kotlin.android") version "2.0.21"
}

android {
    namespace = "com.mobilewebbridge.consumer"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    // 此处不得替换为 project(:mwb) 或生产源码，以保留发布边界验证。
    implementation("io.github.gaoxiao228:mobile-web-bridge:${providers.gradleProperty("mwbVersion").getOrElse("0.1.8")}")
}

tasks.register("verifyPublishedRuntimeDependencies") {
    doLast {
        // 解析真实 POM 的传递依赖，避免只有 AAR 可下载但运行依赖缺失。
        val modules = configurations.getByName("releaseRuntimeClasspath")
            .incoming.resolutionResult.allComponents.mapNotNull {
                it.id as? org.gradle.api.artifacts.component.ModuleComponentIdentifier
            }.map { "${it.group}:${it.module}:${it.version}" }.toSet()
        check("androidx.appcompat:appcompat:1.7.0" in modules)
        check("com.google.mlkit:barcode-scanning:17.3.0" in modules)
        for (artifact in listOf("camera-camera2", "camera-lifecycle", "camera-view")) {
            check("androidx.camera:$artifact:1.4.2" in modules)
        }
        // bundled 内部使用 play-services-mlkit-barcode-scanning，不等同于旧扫码 UI。
        check(modules.none { it.startsWith("com.google.android.gms:play-services-code-scanner:") })
    }
}
