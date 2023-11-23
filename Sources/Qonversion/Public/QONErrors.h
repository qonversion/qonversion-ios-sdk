#import <Foundation/Foundation.h>

extern NSErrorDomain const QONErrorDomain NS_SWIFT_NAME(Qonversion.ErrorDomain);

/*
 Most errors returned by Qonversion SDK contains helpAnchor info.
 For more detailed error description for debug you can use NSError property .helpAnchor
 */

typedef NS_ERROR_ENUM(QONErrorDomain, QONError) {
  QONErrorUnknown = 0,
  
  // user cancelled the request, etc.
  QONErrorCancelled = 1,
  
  // the product has not been added in Qonversion Dashboard
  // see more https://qonversion.io/docs/create-products
  QONErrorProductNotFound = 2,
  
  // client is not allowed to issue the request, etc
  QONErrorClientInvalid = 3,
  
  // purchase identifier was invalid, etc.
  QONErrorPaymentInvalid = 4,
  
  // this device is not allowed to make the payment
  QONErrorPaymentNotAllowed = 5,
  
  // Apple Store didn't process the request
  
  QONErrorStoreFailed = 6,
  
  // product is not available in the current storefront
  QONErrorStoreProductNotAvailable = 7,
  
  // user has not allowed access to cloud service information
  QONErrorCloudServicePermissionDenied = 8,
  
  // the device could not connect to the network
  QONErrorCloudServiceNetworkConnectionFailed = 9,
  
  // user has revoked permission to use this cloud service
  QONErrorCloudServiceRevoked = 10,
  
  // user needs to acknowledge Apple's privacy policy
  QONErrorPrivacyAcknowledgementRequired = 11,
  
  // app is attempting to use SKPayment's requestData property, but does not have the appropriate entitlement
  QONErrorUnauthorizedRequestData = 12,
  
  // provided shared secret is incorrect, validation unavailable
  QONErrorIncorrectSharedSecret = 13,
  
  // failed to connect to Qonversion Backend
  QONErrorConnectionFailed = 14,
  
  // Other URL Session errors
  QONErrorInternetConnectionFailed = 15,
  
  // Network data error
  QONErrorDataFailed = 16,
  
  // Internal error occurred
  QONErrorInternalError = 17,
  
  // The paymet was deferred
  QONErrorStorePaymentDeferred = 18,
  
  // No remote configuration for the current user
  QONErrorRemoteConfigurationNotAvailable = 19,
  
} NS_SWIFT_NAME(Qonversion.Error);


typedef NS_ERROR_ENUM(QONErrorDomain, QONAPIError) {
  // Could not receive data
  QONAPIErrorFailedReceiveData = 0,
  
  // Could not parse response
  QONAPIErrorFailedParseResponse = 1,
  
  // Request failed
  QONAPIErrorIncorrectRequest = 2,
  
  // Internal backend error
  QONAPIErrorInternalError = 3,
  
  // An unknown error occurred
  QONAPIErrorUnknown = 4,
  
  // Invalid credentials in request
  QONAPIErrorInvalidCredentials = 5,
  
  // Invalid client uid received
  QONAPIErrorInvalidClientUID = 6,
  
  // An unknonw client platform error
  QONAPIErrorUnknownClientPlatform = 7,
  
  // Fraud purchase detected
  QONAPIErrorFraudPurchase = 8,
  
  // Requested feature not supported
  QONAPIErrorFeatureNotSupported = 9,
  
  // Apple Store error received
  QONAPIErrorAppleStoreError = 10,
  
  // Invalid purchase error
  QONAPIErrorPurchaseInvalid = 11,
  
  // Project config error. Update project settings on the Qonversion Dashboard
  QONAPIErrorProjectConfigError  = 12,
  
  // Invalid Apple Store credentials error
  QONAPIErrorInvalidStoreCredentials  = 13,
  
  // Receipt validation error
  QONAPIErrorReceiptValidation = 14,

  // Rate limit exceeded
  QONAPIErrorRateLimitExceeded = 15,
} NS_SWIFT_NAME(Qonversion.APIError);

@interface QONErrors: NSObject

+ (NSError *)errorWithCode:(QONError)errorCode message:(NSString *)message;
+ (NSError *)errorWithCode:(QONAPIError)errorCode;
+ (NSError *)errorWithCode:(QONAPIError)errorCode message:(NSString *)message failureReason:(NSString *)failureReason;
+ (NSError *)errorWithQONErrorCode:(QONError)errorCode;
+ (NSError *)errorFromURLDomainError:(NSError *)error;
+ (NSError *)errorFromTransactionError:(NSError *)error;
+ (NSError *)deferredTransactionError;

@end

