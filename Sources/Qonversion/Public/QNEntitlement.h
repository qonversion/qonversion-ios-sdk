#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, QNEntitlementSource) {
   QNEntitlementSourceUnknown = -1, // Unable to detect the source
   QNEntitlementSourceAppStore = 1, // App Store
   QNEntitlementSourcePlayStore = 2, // Play Store
   QNEntitlementSourceStripe = 3, // Stripe
   QNEntitlementSourceManual = 4 // The entitlement was activated manually
 } NS_SWIFT_NAME(Qonversion.EntitlementSource);

typedef NS_ENUM(NSInteger, QNEntitlementRenewState){
  /**
   For in-app purchases.
   */
  QNEntitlementRenewStateNonRenewable = -1,
  /**
    Unknown state
   */
  QNEntitlementRenewStateUnknown = 0,
  
  /**
    Subscription is active and will renew
   */
  QNEntitlementRenewStateWillRenew = 1,
  
  /**
   The user canceled the subscription, but the subscription may be active.
   Check isActive to be sure that the subscription has not expired yet.
   */
  QNEntitlementRenewStateCancelled = 2,
  
  /**
   There was some billing issue.
   Prompt the user to update the payment method.
   */
  QNEntitlementRenewStateBillingIssue = 3
} NS_SWIFT_NAME(Qonversion.EntitlementRenewState);

NS_SWIFT_NAME(Qonversion.Entitlement)
@interface QNEntitlement : NSObject <NSCoding>

/**
 Qonversion Entitlement ID, like premium
 @see [Create Entitlement](https://qonversion.io/docs/create-permission)
 */
@property (nonatomic, copy, nonnull) NSString *entitlementID;

/**
 Product ID created in Qonversion Dashboard
 @see [Create Products](https://qonversion.io/docs/create-products)
 */
@property (nonatomic, copy, nonnull) NSString *productID;

/**
 Use for checking entitlement for current user
 Pay attention, isActive = true not mean that subscription is renewable
 Subscription could be canceled, but the user still has an entitlement
 */
@property (nonatomic) BOOL isActive;

/**
 A renew state for an associate product that unlocked entitlement
 */
@property (nonatomic, assign) QNEntitlementRenewState renewState;

/**
  Source of the purchase via which the entitlement was activated.
 */
@property (nonatomic, assign) QNEntitlementSource source;

/**
 Purchase date
 */
@property (nonatomic, copy, nonnull) NSDate *startedDate;

/**
 Expiration date for subscriptions
 */
@property (nonatomic, copy, nullable) NSDate *expirationDate;

@end
