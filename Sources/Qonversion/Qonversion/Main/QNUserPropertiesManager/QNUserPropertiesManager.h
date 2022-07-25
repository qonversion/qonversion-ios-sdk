#import <Foundation/Foundation.h>

@class QNProductCenterManager;

NS_ASSUME_NONNULL_BEGIN

@interface QNUserPropertiesManager : NSObject

@property (nonatomic, strong) QNProductCenterManager *productCenterManager;

- (void)setUserProperty:(NSString *)property value:(NSString *)value;
@end

NS_ASSUME_NONNULL_END
