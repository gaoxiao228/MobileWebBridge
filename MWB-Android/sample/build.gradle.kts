plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }

android {
    namespace = "com.mobilewebbridge.sample"
    compileSdk = 35
    defaultConfig { applicationId = "com.mobilewebbridge.sample"; minSdk = 24; targetSdk = 35; versionCode = 1; versionName = "0.1.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    testOptions { unitTests.isIncludeAndroidResources = true }
    buildTypes {
        getByName("release") {
            // 用消费端 R8 构建验证库提供的注解保留规则。
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
}

dependencies {
    implementation(project(":mwb"))
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
}
