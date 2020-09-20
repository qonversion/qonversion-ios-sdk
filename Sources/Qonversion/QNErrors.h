#import <Foundation/Foundation.h>
#import "QNConstants.h"

extern NSErrorDomain const QNErrorDomain NS_SWIFT_NAME(Qonversion.ErrorDomain);

typedef NS_ERROR_ENUM(QNErrorDomain, QNError) {
  QNErrorUnknown = 0,
  
  // user cancelled the request, etc.
  QNErrorCancelled,
  
  // the product has not been added to the product center
  // see more https://qonversion.io/docs/create-products
  QNErrorProductNotFound,
  
  // client is not allowed to issue the request, etc
  QNErrorClientInvalid,
  
  // purchase identifier was invalid, etc.
  QNErrorPaymentInvalid,
  
  // this device is not allowed to make the payment
  QNErrorPaymentNotAllowed,
  
  // Apple Store didn't processe request
  
  QNErrorStoreFailed,
  
  // product is not available in the current storefront
  QNErrorStoreProductNotAvailable,
  
  // user has not allowed access to cloud service information
  QNErrorCloudServicePermissionDenied,
  
  // the device could not connect to the nework
  QNErrorCloudServiceNetworkConnectionFailed,
  
  // user has revoked permission to use this cloud service
  QNErrorCloudServiceRevoked,
  
  // user needs to acknowledge Apple's privacy policy
  QNErrorPrivacyAcknowledgementRequired,
  
  // app is attempting to use SKPayment's requestData property, but does not have the appropriate entitlement
  QNErrorUnauthorizedRequestData,
  
  // provided shared secret is incorrect, validation unavailable
  QNErrorIncorrectSharedSecret,
  
  // failed to connect to Qonversion Backend
  QNErrorConnectionFailed,
  
  // Other URL Session errors
  QNErrorInternetConnectionFailed,
  
  // Network data error
  QNErrorDataFailed,
  
  // Internal error occurred
  QNErrorInternalError,
  
} NS_SWIFT_NAME(Qonversion.Error);


typedef NS_ERROR_ENUM(QNErrorDomain, QNAPIError) {
  QNAPIErrorFailedReceiveData = 0,
  QNAPIErrorFailedParseResponse,
  QNAPIErrorIncorrectRequest
};

@interface QNErrors: NSObject

+ (NSError *)errorWithCode:(QNAPIError)errorCode;
+ (NSError *)errorWithQNErrorCode:(QNError)errorCode;
+ (NSError *)errorFromURLDomainError:(NSError *)error;
+ (NSError *)errorFromTransactionError:(NSError *)error;

@end

