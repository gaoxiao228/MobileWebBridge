# 第三方源码

`mwb/src/main/java/wendu/dsbridge/` 包含 [wendux/DSBridge-Android](https://github.com/wendux/DSBridge-Android/tree/3.0.0) 3.0.0 的 `DWebView.java`、`CompletionHandler.java`、`OnReturnValue.java`，来源提交 `d3e5ebc6ca8170f97e420f2f482680c8e149b471`。上游 README 的许可证徽章指向 MIT 许可证。`DWebView.java` 为兼容 AndroidX/SDK 35 并避免修改宿主全局 Cookie 做了少量改动；主线程 `loadUrl` 直接发起导航，后台线程调用仍由 Handler 转发。

原生插件扩展额外修改 `CompletionHandler.java`：新增默认 `completeForDocument`，保持原有调用方式兼容；`DWebView.java` 新增文档受守卫的回调、事件发送路径。新增本项目的 `DocumentScriptGuard.java` 在 JS 实际执行时通过同步 `mwb.pluginSession` 校验原生文档身份，防止旧文档脚本调用或删除新文档同名回调；basic 仍使用原上游完成和事件路径。

测试依赖 Mozilla Rhino 1.7.15（MPL 2.0）仅用于 JVM 执行生成的守卫脚本，不打入 AAR/APK 运行时依赖。

---

# DSBridge third-party notice

DSBridge JavaScript 3.1.4: https://www.npmjs.com/package/dsbridge/v/3.1.4
DSBridge Android 3.0.0: https://github.com/wendux/DSBridge-Android/tree/d3e5ebc6ca8170f97e420f2f482680c8e149b471
DSBridge iOS 3.0.6: https://github.com/wendux/DSBridge-IOS/tree/f0e3c724dd362800528f8b6c788bdad7006cc187

Author: wendux (杜文 / Du Wen), as identified by upstream package metadata and source.
The upstream npm metadata, Android readme.md and iOS podspec declare MIT.
The pinned native trees do not provide a separate LICENSE file; the MIT terms
are reproduced below without inventing an absent upstream copyright notice.
Original iOS source notices are retained verbatim:

Copyright © 2016年 杜文. All rights reserved.
Copyright © 2018年 杜文. All rights reserved.

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
