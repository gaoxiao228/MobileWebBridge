# 安全与可信来源

MWB 当前为公开 Beta 阶段：JS `0.1.1-beta.1` 已发布 npm，原生为 `0.1.0` 源码/本机制品。暂无稳定版或长期支持承诺。版本与支持范围见 [版本说明](docs/versioning.md)。

容器只应加载宿主控制的页面。allowedOrigins 限制页面来源，不能防止可信页面自身的 XSS。Android DSBridge JavascriptInterface 会进入所有 frame，页面不得嵌入不可信 frame；插件 documentId 仅用于生命周期隔离。业务插件仍需校验参数、账号状态和业务权限。

正式仓库为 [gaoxiao228/MobileWebBridge](https://github.com/gaoxiao228/MobileWebBridge)，维护者主页为 [gaoxiao228](https://github.com/gaoxiao228)。常规功能问题使用 [Issues](https://github.com/gaoxiao228/MobileWebBridge/issues)。

涉及漏洞时，优先使用仓库的 [私密漏洞报告入口](https://github.com/gaoxiao228/MobileWebBridge/security/advisories/new)。该入口必须先由维护者在仓库 Settings → Security → Private vulnerability reporting 中启用；本次仅补充配置和说明，未修改 GitHub 设置，也未确认该入口已启用。如果没有私密报告入口，请先联系维护者确认私密渠道，暂不提交漏洞细节；本项目没有虚构或承诺已监控的安全邮箱。

不要在公开 Issue、截图或日志中提交密钥、证书、用户数据、内部地址或可直接利用的漏洞细节。维护者应在邀请公开试用前完成上述渠道配置和一次接收验证。

报告请提供受影响版本、平台/WebView 版本、最小复现条件、实际行为和预期行为，并移除真实用户数据。涉及敏感信息或漏洞细节时，应等待私密渠道就绪。
