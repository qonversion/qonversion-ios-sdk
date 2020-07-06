#import <Foundation/Foundation.h>

NS_SWIFT_NAME(Qonversion.Errors)
@interface QErrors

extern NSErrorDomain const QonversionErrorDomain NS_SWIFT_NAME(Qonversion.ErrorDomain);

typedef NS_ERROR_ENUM(QonversionErrorDomain, QonversionError) {
  QonversionErrorUnknown = 0,
  
  // user cancelled the request, etc.
  QonversionErrorCancelled,
  
  // the product has not been added to the product center
  // see more https://qonversion.io/docs/create-products
  QonversionErrorProductNotFound,
  
  // client is not allowed to issue the request, etc
  QonversionErrorClientInvalid,
  
  // purchase identifier was invalid, etc.
  QonversionErrorPaymentInvalid,
  
  // this device is not allowed to make the payment
  QonversionErrorPaymentNotAllowed,
  
  // Apple Store didn't processe request
  
  QonversionErrorStoreFailed,
  
  // product is not available in the current storefront
  QonversionErrorStoreProductNotAvailable,
  
  // user has not allowed access to cloud service information
  QonversionErrorCloudServicePermissionDenied,
  
  // the device could not connect to the nework
  QonversionErrorCloudServiceNetworkConnectionFailed,
  
  // user has revoked permission to use this cloud service
  QonversionErrorCloudServiceRevoked,
  
  // user needs to acknowledge Apple's privacy policy
  QonversionErrorPrivacyAcknowledgementRequired,
  
  // app is attempting to use SKPayment's requestData property, but does not have the appropriate entitlement
  QonversionErrorUnauthorizedRequestData,
  
  // provided shared secret is incorrect, validation unavailable
  QonversionErrorIncorrectSharedSecret,
  
  // failed to connect to Qonversion Backend
  QonversionErrorConnectionFailed,
  
  // Other URL Session errors
  QonversionErrorInternetConnectionFailed,
  
  // Network data error
  QonversionErrorDataFailed,
  
} NS_SWIFT_NAME(Qonversion.Error);

@end
