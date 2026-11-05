# DSBridge 通过反射查找 @JavascriptInterface 方法。
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# 业务插件按运行时注解和精确参数类型查找，保留名称、签名及运行时注解。
-keepattributes RuntimeVisibleAnnotations
-keep @interface com.mobilewebbridge.plugins.MWBMethod
-keep class com.mobilewebbridge.plugins.MWBPluginCallContext { *; }
-keep class com.mobilewebbridge.plugins.MWBPluginResponder { *; }
-keepclassmembers class * extends com.mobilewebbridge.plugins.MWBPlugin {
    @com.mobilewebbridge.plugins.MWBMethod <methods>;
}
# 基类是方法扫描的终止边界，禁止 R8 将其合并进唯一业务子类。
-keep class com.mobilewebbridge.plugins.MWBPlugin { *; }
