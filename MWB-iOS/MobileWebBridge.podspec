Pod::Spec.new do |s|
  s.name = 'MobileWebBridge'
  s.version = '0.1.2'
  s.summary = 'Swift Web container powered by DSBridge'
  # 子目录保留 Example 的本地 :path 接入，Git 接入使用仓库根目录的 podspec。
  s.homepage = 'https://github.com/gaoxiao228/MobileWebBridge'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'gaoxiao228'
  # 本轮三端统一为 0.1.2，共用对应的仓库源码 Tag。
  s.source = { :git => 'https://github.com/gaoxiao228/MobileWebBridge.git', :tag => '0.1.2' }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'
  s.source_files = 'Sources/**/*.{swift,h,m}', 'Vendor/DSBridge/*.{h,m}'
  s.public_header_files = 'Vendor/DSBridge/*.h', 'Sources/Plugins/MWBPluginException.h'
  # 保留第三方许可；LICENSE同时供CocoaPods生成宿主Acknowledgements。
  s.preserve_paths = 'LICENSE', 'THIRD_PARTY_NOTICES.md'
  # 独立资源 Bundle 随静态或动态框架宿主复制，避免隐私清单只存在于源码目录。
  s.resource_bundles = {
    'MobileWebBridgePrivacy' => ['Resources/PrivacyInfo.xcprivacy'],
    'MobileWebBridgeErrorPage' => ['Resources/ErrorPage/*']
  }
  s.frameworks = 'WebKit'
end
