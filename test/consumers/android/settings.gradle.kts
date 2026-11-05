pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}

// 独立工程只按坐标消费发布物；必须由调用者传入文件 Maven 仓库。
val mwbRepository = providers.gradleProperty("mwbRepository").get()
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        exclusiveContent {
            forRepository {
                maven {
                    url = uri(mwbRepository)
                    // 强制读取 POM，避免 Gradle Module Metadata 掩盖 POM 依赖缺失。
                    metadataSources { mavenPom(); artifact(); ignoreGradleMetadataRedirection() }
                }
            }
            filter { includeGroup("io.github.gaoxiao228") }
        }
        google()
        mavenCentral()
    }
}
rootProject.name = "MwbPublishedConsumer"
