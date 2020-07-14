#import <Foundation/Foundation.h>
#import "QNProduct.h"
#import "QNPermission.h"

typedef void (^QNPermissionCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.PermissionCompletionHandler);

typedef void (^QNPurchaseCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error, BOOL cancelled) NS_SWIFT_NAME(Qonversion.PurchaseCompletionHandler);

NS_ASSUME_NONNULL_BEGIN

@interface QNProductCenterManager : NSObject

@end

NS_ASSUME_NONNULL_END
