#import <Foundation/Foundation.h>
#import "QNConstants.h"

extern NSErrorDomain const QNErrorDomain NS_SWIFT_NAME(Qonversion.ErrorDomain);

/*
 Most errors returned by Qonversion SDK contains helpAnchor info.
 For more detailed error description for debug you can use NSError property .helpAnchor
 */

typedef NS_ERROR_ENUM(QNErrorDomain, QNError) {
  QNErrorUnknown = 0,
  
  // user cancelled the request, etc.
  QNErrorCancelled = 1,
  
  // the product has not been added to the product center
  // see more https://qonversion.io/docs/create-products
  QNErrorProductNotFound = 2,
  
  // client is not allowed to issue the request, etc
  QNErrorClientInvalid = 3,
  
  // purchase identifier was invalid, etc.
  QNErrorPaymentInvalid = 4,
  
  // this device is not allowed to make the payment
  QNErrorPaymentNotAllowed = 5,
  
  // Apple Store didn't process the request
  
  QNErrorStoreFailed = 6,
  
  // product is not available in the current storefront
  QNErrorStoreProductNotAvailable = 7,
  
  // user has not allowed access to cloud service information
  QNErrorCloudServicePermissionDenied = 8,
  
  // the device could not connect to the network
  QNErrorCloudServiceNetworkConnectionFailed = 9,
  
  // user has revoked permission to use this cloud service
  QNErrorCloudServiceRevoked = 10,
  
  // user needs to acknowledge Apple's privacy policy
  QNErrorPrivacyAcknowledgementRequired = 11,
  
  // app is attempting to use SKPayment's requestData property, but does not have the appropriate entitlement
  QNErrorUnauthorizedRequestData = 12,
  
  // provided shared secret is incorrect, validation unavailable
  QNErrorIncorrectSharedSecret = 13,
  
  // failed to connect to Qonversion Backend
  QNErrorConnectionFailed = 14,
  
  // Other URL Session errors
  QNErrorInternetConnectionFailed = 15,
  
  // Network data error
  QNErrorDataFailed = 16,
  
  // Internal error occurred
  QNErrorInternalError = 17,
  
  QNErrorStorePaymentDeferred = 18,
  
} NS_SWIFT_NAME(Qonversion.Error);


typedef NS_ERROR_ENUM(QNErrorDomain, QNAPIError) {
  // Could not receive data
  QNAPIErrorFailedReceiveData = 0,
  
  // Could not parse response
  QNAPIErrorFailedParseResponse = 1,
  
  // Request failed
  QNAPIErrorIncorrectRequest = 2,
  
  // Internal backend error
  QNAPIErrorInternalError = 3,
  
  // An unknown error occurred
  QNAPIErrorUnknown = 4,
  
  // Invalid credentials in request
  QNAPIErrorInvalidCredentials = 5,
  
  // Invalid client uid received
  QNAPIErrorInvalidClientUID = 6,
  
  // An unknonw client platform error
  QNAPIErrorUnknownClientPlatform = 7,
  
  // Fraud purchase detected
  QNAPIErrorFraudPurchase = 8,
  
  // Requested feature not supported
  QNAPIErrorFeatureNotSupported = 9,
  
  // Apple Store error received
  QNAPIErrorAppleStoreError = 10,
  
  // Invalid purchase error
  QNAPIErrorPurchaseInvalid = 11,
  
  // Project config error. Update project settings on the Qonversion Dashboard
  QNAPIErrorProjectConfigError  = 12,
  
  // Invalid Apple Store credentials error
  QNAPIErrorInvalidStoreCredentials  = 13,
  
  // Receipt validation error
  QNAPIErrorReceiptValidation = 14
};

@interface QNErrors: NSObject

+ (NSError *)errorWithCode:(QNAPIError)errorCode;
+ (NSError *)errorWithCode:(QNAPIError)errorCode message:(NSString *)message failureReason:(NSString *)failureReason;
+ (NSError *)errorWithQNErrorCode:(QNError)errorCode;
+ (NSError *)errorFromURLDomainError:(NSError *)error;
+ (NSError *)errorFromTransactionError:(NSError *)error;
+ (NSError *)deferredTransactionError;

@end

