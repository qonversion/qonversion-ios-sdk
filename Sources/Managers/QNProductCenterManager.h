#import <Foundation/Foundation.h>
#import "QNProduct.h"
#import "QNPermission.h"
#import "Qonversion.h"

@class QNLaunchResult;

NS_ASSUME_NONNULL_BEGIN

@interface QNProductCenterManager : NSObject

- (void)launchWithCompletion:(QNLaunchCompletionHandler)completion;
- (void)checkPermissions:(QNPermissionCompletionHandler)completion;
- (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion;
- (void)restoreWith:(QNPurchaseCompletionHandler)completion;

- (void)products:(QNProductsCompletionHandler)completion;

- (void)launch:(void (^)(QNLaunchResult * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
