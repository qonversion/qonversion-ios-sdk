#import <Foundation/Foundation.h>

extern NSErrorDomain const QONErrorDomain NS_SWIFT_NAME(Qonversion.ErrorDomain);

/*
 Most errors returned by Qonversion SDK contains helpAnchor info.
 For more detailed error description for debug you can use NSError property .helpAnchor
 */

typedef NS_ERROR_ENUM(QONErrorDomain, QONErrorCode) {
  QONErrorCodeUnknown = 0,
  
  // user cancelled the purchase request, etc.
  QONErrorCodePurchaseCanceled = 1,
  
  // the product has not been added in Qonversion Dashboard
  QONErrorCodeProductNotFound = 2,
  
  // client is not allowed to issue the request, etc
  QONErrorCodeClientInvalid = 3,
  
  // purchase identifier was invalid, etc.
  QONErrorCodePaymentInvalid = 4,
  
  // this device is not allowed to make the payment
  QONErrorCodePaymentNotAllowed = 5,
  
  // product is not available in the current storefront
  QONErrorCodeStoreProductNotAvailable = 7,
  
  // user has not allowed access to cloud service information
  QONErrorCodeCloudServicePermissionDenied = 8,
  
  // the device could not connect to the network
  QONErrorCodeCloudServiceNetworkConnectionFailed = 9,
  
  // user has revoked permission to use this cloud service
  QONErrorCodeCloudServiceRevoked = 10,
  
  // user needs to acknowledge Apple's privacy policy
  QONErrorCodePrivacyAcknowledgementRequired = 11,
  
  // app is attempting to use SKPayment's requestData property, but does not have the appropriate entitlement
  QONErrorCodeUnauthorizedRequestData = 12,

  // failed to connect to Qonversion Backend
  QONErrorCodeNetworkConnectionFailed = 14,

  // Internal error occurred
  QONErrorCodeInternalError = 17,
  
  // The payment was deferred
  QONErrorCodePurchasePending = 18,
  
  // No remote configuration for the current user
  QONErrorCodeRemoteConfigurationNotAvailable = 19,

  // Could not receive data
  QONErrorCodeFailedToReceiveData = 20,
  
  // Could not parse response
  QONErrorCodeResponseParsingFailed = 21,
  
  // Request failed
  QONErrorCodeIncorrectRequest = 22,
  
  // Internal backend error
  QONErrorCodeBackendError = 23,

  // Invalid credentials in request
  QONErrorCodeInvalidCredentials = 25,
  
  // Invalid client uid received
  QONErrorCodeInvalidClientUID = 26,
  
  // An unknown client platform error
  QONErrorCodeUnknownClientPlatform = 27,
  
  // Fraud purchase detected
  QONErrorCodeFraudPurchase = 28,
  
  // Requested feature not supported
  QONErrorCodeFeatureNotSupported = 29,
  
  // Apple Store error received
  QONErrorCodeAppleStoreError = 30,
  
  // Invalid purchase error
  QONErrorCodePurchaseInvalid = 31,
  
  // Project config error. Update project settings on the Qonversion Dashboard
  QONErrorCodeProjectConfigError = 32,
  
  // Invalid Apple Store credentials error
  QONErrorCodeInvalidStoreCredentials = 33,
  
  // Receipt validation error
  QONErrorCodeReceiptValidationError = 34,

  // Rate limit exceeded
  QONErrorCodeApiRateLimitExceeded = 35,
  
  // No offerings for the current user
  QONErrorCodeOfferingsNotAvailable = 36,
  
} NS_SWIFT_NAME(Qonversion.ErrorCode);

@interface QONErrors: NSObject

+ (NSError *)internalErrorWithCode:(QONErrorCode)errorCode;
+ (NSError *)errorWithCode:(QONErrorCode)errorCode message:(NSString *)message;
+ (NSError *)errorWithCode:(QONErrorCode)errorCode message:(NSString *)message failureReason:(NSString *)failureReason;
+ (NSError *)errorWithQONErrorCode:(QONErrorCode)errorCode;
+ (NSError *)errorFromURLDomainError:(NSError *)error;
+ (NSError *)errorFromTransactionError:(NSError *)error;
+ (NSError *)deferredTransactionError;
+ (NSError *)emptyOfferingsError;

@end

