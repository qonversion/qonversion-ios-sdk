#import <Foundation/Foundation.h>

typedef NS_ENUM(unsigned int, QonversionPermissionRenewState){
    QonversionPermissionRenewStateNonRenewable = -1,
    QonversionPermissionRenewStateWillRenew = 0,
    QonversionPermissionRenewStateCancelled = 1,
    QonversionPermissionRenewStateBillingIssue = 2
};

@interface QonversionPermissionResult : NSObject

/**
 Qonversion Permission, like premium
 https://qonversion.io/create-permission
 */
@property (nonatomic, copy) NSString *permissionID;

/**
 Product ID created in Qonversion Dashboard
 https://qonversion.io/create-products
 */
@property (nonatomic, copy) NSString *qonversionProductID;

/**
 Use for checking permission for current user
 Pay attention, isActive = true not mean that subscription is renewable
 Subscription could be canceled, but the user still has a permission
 */
@property (nonatomic) BOOL isActive;

/**
 A renew state for an associate product that unlocked permission
 */
@property (nonatomic) QonversionPermissionRenewState renewState;

/**
 Purchase date
 */
@property (nonatomic, copy) NSDate *startedDate;

/**
 Expiration date for subscriptions
 */
@property (nonatomic, copy, nullable) NSDate *expirationDate;

@end
