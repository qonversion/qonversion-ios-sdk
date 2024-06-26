#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

@class QNProductCenterManager, QONUserPropertiesMapper;

NS_ASSUME_NONNULL_BEGIN

typedef void (^QONUserPropertiesEmptyCompletionHandler)(void) NS_SWIFT_NAME(Qonversion.UserPropertiesEmptyCompletionHandler);

@interface QNUserPropertiesManager : NSObject

@property (nonatomic, strong) QNProductCenterManager *productCenterManager;
@property (nonatomic, strong) QONUserPropertiesMapper *mapper;

- (void)setUserProperty:(NSString *)property value:(NSString *)value;
- (void)getUserProperties:(QONUserPropertiesCompletionHandler)completion;
- (void)forceSendProperties:(QONUserPropertiesEmptyCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
