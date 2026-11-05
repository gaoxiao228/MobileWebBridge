plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.vanniktech.maven.publish.base")
    id("org.jetbrains.dokka")
}

// 坐标须先通过 Central 命名空间认证；配置存在不代表已经公开发布。
group = "io.github.gaoxiao228"
version = providers.gradleProperty("mwbVersion").getOrElse("0.1.0")

android {
    namespace = "com.mobilewebbridge"
    compileSdk = 35
    defaultConfig { minSdk = 24; consumerProguardFiles("consumer-rules.pro") }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    testOptions { unitTests.isIncludeAndroidResources = true }
    publishing { singleVariant("release") { withSourcesJar() } }
}

// 由 Dokka 生成 Kotlin/Java API 文档，实际内容随 Maven 的 javadoc 制品分发。
val javadocJar by tasks.registering(Jar::class) {
    archiveClassifier.set("javadoc")
    from(tasks.named("dokkaGeneratePublicationHtml"))
}

// 日常构建和本地发布不需要密钥；只有显式 Central 发布模式才启用上传与签名。
if (providers.gradleProperty("mwbCentral").map { it.toBooleanStrict() }.getOrElse(false)) {
    mavenPublishing {
        publishToMavenCentral(automaticRelease = false)
        signAllPublications()
    }
}

publishing {
    repositories {
        // 保留独立接入检查使用的本地仓库，避免验证流程触发远程上传。
        maven {
            name = "LocalIntegration"
            url = rootProject.layout.buildDirectory.dir("maven-repository").get().asFile.toURI()
        }
    }
    publications {
        register<MavenPublication>("release") {
            artifactId = "mobile-web-bridge"
            artifact(javadocJar)
            // AGP 在项目评估后创建组件；从组件发布才能保留 POM 的传递依赖。
            afterEvaluate { from(components["release"]) }
            pom {
                name.set("MobileWebBridge")
                description.set("Android WebView bridge container with explicit host and plugin integration.")
                url.set("https://github.com/gaoxiao228/MobileWebBridge")
                licenses {
                    license {
                        name.set("MIT License")
                        url.set("https://opensource.org/licenses/MIT")
                        distribution.set("repo")
                    }
                }
                developers {
                    developer {
                        id.set("gaoxiao228")
                        name.set("gaoxiao228")
                        url.set("https://github.com/gaoxiao228")
                    }
                }
                scm {
                    url.set("https://github.com/gaoxiao228/MobileWebBridge")
                    connection.set("scm:git:https://github.com/gaoxiao228/MobileWebBridge.git")
                    developerConnection.set("scm:git:ssh://git@github.com/gaoxiao228/MobileWebBridge.git")
                }
            }
        }
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mozilla:rhino:1.7.15")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
}

// 将库自身及vendored DSBridge许可放进classes.jar，消费端AAR也能保留声明。
val prepareMwbLicenses by tasks.registering(Sync::class) {
    into(layout.buildDirectory.dir("generated/mwb-licenses"))
    into("META-INF/mobile-web-bridge") {
        from(project.file("../LICENSE"), project.file("../THIRD_PARTY_NOTICES.md"))
    }
}
android.sourceSets.getByName("main").resources.srcDir(prepareMwbLicenses)
// Android Java资源任务不推导srcDir传入任务的依赖，显式在preBuild生成。
tasks.named("preBuild") { dependsOn(prepareMwbLicenses) }
