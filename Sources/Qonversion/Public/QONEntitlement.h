#import <Foundation/Foundation.h>
#import "QONTransaction.h"

typedef NS_ENUM(NSInteger, QONEntitlementSource) {
   QONEntitlementSourceUnknown = -1, // Unable to detect the source
   QONEntitlementSourceAppStore = 1, // App Store
   QONEntitlementSourcePlayStore = 2, // Play Store
   QONEntitlementSourceStripe = 3, // Stripe
   QONEntitlementSourceManual = 4 // The entitlement was activated manually
 } NS_SWIFT_NAME(Qonversion.EntitlementSource);

typedef NS_ENUM(NSInteger, QONEntitlementGrantType) {
  QONEntitlementGrantTypePurchase = 0,
  QONEntitlementGrantTypeFamilySharing = 1,
  QONEntitlementGrantTypeOfferCode = 2,
  QONEntitlementGrantTypeManual = 3
 } NS_SWIFT_NAME(Qonversion.EntitlementGrantType);

typedef NS_ENUM(NSInteger, QONEntitlementRenewState){
  /**
   For in-app purchases.
   */
  QONEntitlementRenewStateNonRenewable = -1,
  /**
    Unknown state
   */
  QONEntitlementRenewStateUnknown = 0,
  
  /**
    Subscription is active and will renew
   */
  QONEntitlementRenewStateWillRenew = 1,
  
  /**
   The user canceled the subscription, but the subscription may be active.
   Check isActive to be sure that the subscription has not expired yet.
   */
  QONEntitlementRenewStateCancelled = 2,
  
  /**
   There was some billing issue.
   Prompt the user to update the payment method.
   */
  QONEntitlementRenewStateBillingIssue = 3
} NS_SWIFT_NAME(Qonversion.EntitlementRenewState);

NS_SWIFT_NAME(Qonversion.Entitlement)
@interface QONEntitlement : NSObject <NSCoding>

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
@property (nonatomic, assign) QONEntitlementRenewState renewState;

/**
  Source of the purchase via which the entitlement was activated.
 */
@property (nonatomic, assign) QONEntitlementSource source;

/**
 Purchase date
 */
@property (nonatomic, copy, nonnull) NSDate *startedDate;

/**
 Expiration date for subscriptions
 */
@property (nonatomic, copy, nullable) NSDate *expirationDate;

/**
 Renews count for the entitlement. Renews count starts from the second paid subscription.
 For example, we have 20 transactions. One is the trial, and one is the first paid transaction after the trial.
 Renews count is equal to 18.
 */
@property (nonatomic, assign) NSUInteger renewsCount;

/**
 Trial start date.
 */
@property (nonatomic, strong, nullable) NSDate *trialStartDate;

/**
 First purchase date.
 */
@property (nonatomic, strong, nullable) NSDate *firstPurchaseDate;

/**
 Last purchase date.
 */
@property (nonatomic, strong, nullable) NSDate *lastPurchaseDate;

/**
 Last activated offer code.
 */
@property (nonatomic, copy, nullable) NSString *lastActivatedOfferCode;

/**
 Grant type of the entitlement.
 */
@property (nonatomic, assign) QONEntitlementGrantType grantType;

/**
 Auto-renew disable date.
 */
@property (nonatomic, strong, nullable) NSDate *autoRenewDisableDate;

/**
 Array of the transactions that unlocked current entitlement.
 */
@property (nonatomic, copy, nonnull) NSArray<QONTransaction *> *transactions;

@end
