#import "MWBPluginException.h"

NSString *MWBPluginTry(void (^operation)(void)) {
    @try {
        operation();
        return nil;
    } @catch (NSException *exception) {
        // 不向网页泄露宿主内部异常细节。
        return exception.name;
    }
}
