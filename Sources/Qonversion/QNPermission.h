#import <Foundation/Foundation.h>

typedef NS_ENUM(int, QNPermissionRenewState){
  /**
   For in-app purchases.
   */
  QNPermissionRenewStateNonRenewable = -1,
  QNPermissionRenewStateUnknown = 0,
  
  /**
    Subscription is active and will renew
   */
  QNPermissionRenewStateWillRenew = 1,
  
  /**
   The user canceled the subscription, but the subscription may be active.
   Check isActive to be sure that the subscription has not expired yet.
   */
  QNPermissionRenewStateCancelled = 2,
  
  /**
   There was some billing issue.
   Prompt the user to update the payment method.
   */
  QNPermissionRenewStateBillingIssue = 3
} NS_SWIFT_NAME(Qonversion.PermissionRenewState);

NS_SWIFT_NAME(Qonversion.Permission)
@interface QNPermission : NSObject <NSCoding>

/**
 Qonversion Permission ID, like premium
 @see [Create Permission](https://qonversion.io/docs/create-permission)
 */
@property (nonatomic, copy, nonnull) NSString *permissionID;

/**
 Product ID created in Qonversion Dashboard
 @see [Create Products](https://qonversion.io/docs/create-products)
 */
@property (nonatomic, copy, nonnull) NSString *productID;

/**
 Use for checking permission for current user
 Pay attention, isActive = true not mean that subscription is renewable
 Subscription could be canceled, but the user still has a permission
 */
@property (nonatomic) BOOL isActive;

/**
 A renew state for an associate product that unlocked permission
 */
@property (nonatomic) QNPermissionRenewState renewState;

/**
 Purchase date
 */
@property (nonatomic, copy, nonnull) NSDate *startedDate;

/**
 Expiration date for subscriptions
 */
@property (nonatomic, copy, nullable) NSDate *expirationDate;

@end
