#import <Foundation/Foundation.h>

/// Swift 无法捕获 NSException；只在第三方插件边界将其转换为桥错误。
FOUNDATION_EXPORT NSString * _Nullable MWBPluginTry(void (^ _Nonnull operation)(void));
