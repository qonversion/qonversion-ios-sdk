#import <Foundation/Foundation.h>
#import "QNProduct.h"
#import "QNPermission.h"
#import "Qonversion.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNProductCenterManager : NSObject

- (void)launchWithKey:(nonnull NSString *)key completion:(QNPurchaseCompletionHandler)completion;
- (void)checkPermissions:(QNPermissionCompletionHandler)result;
- (void)purchase:(NSString *)productID result:(QNPurchaseCompletionHandler)result;

@end

NS_ASSUME_NONNULL_END
