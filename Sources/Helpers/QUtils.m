#import <StoreKit/StoreKit.h>

#import "QUtils.h"
#import "QErrors.h"

@implementation QUtils

+ (BOOL)isEmptyString:(NSString *)string {
  return string == nil || [string isKindOfClass:[NSNull class]] || [string length] == 0;
}

+ (NSError *)errorFromTransactionError:(NSError *)error {
  QonversionError errorCode = QonversionErrorUnknown;
  
  if ([[error domain] isEqualToString:SKErrorDomain]) {
    SKErrorCode skErrorCode = error.code;
    SKErrorCloudServiceNetworkConnectionFailed
      switch (skErrorCode) {
        case SKErrorUnknown:
          errorCode = QonversionErrorUnknown; break;
        case SKErrorPaymentCancelled:
          errorCode = QonversionErrorCancelled; break;
        case SKErrorStoreProductNotAvailable:
          errorCode = QonversionErrorStoreProductNotAvailable; break;
        case SKErrorPaymentNotAllowed:
          errorCode = QonversionErrorPaymentNotAllowed; break;
        case SKErrorPaymentInvalid:
          errorCode = QonversionErrorPaymentInvalid; break;
        // Belowe codes available on different iOS
        case 6: // SKErrorCloudServicePermissionDenied
          errorCode = QonversionErrorCloudServicePermissionDenied;
        case 7: // SKErrorCloudServiceNetworkConnectionFailed
          errorCode = QonversionErrorConnectionFailed; break;
        case 8: // SKErrorCloudServiceRevoked
          errorCode = QonversionErrorCloudServiceRevoked; break;
        case 9: // SKErrorPrivacyAcknowledgementRequired
          errorCode = QonversionErrorPrivacyAcknowledgementRequired; break;
        case 10: // SKErrorUnauthorizedRequestData
          errorCode = QonversionErrorUnauthorizedRequestData; break;
      }
  } else {
    return error;
  }
  
  return [self errorWithQonverionErrorCode:errorCode];
}

+ (NSError *)errorWithQonverionErrorCode:(QonversionError)code {
  [[NSError alloc] initWithDomain:QonversionErrorDomain code:code userInfo:nil];
}


+ (NSError *)errorFromURLDomainError:(NSError *)error {
  QonversionError errorCode = QonversionErrorUnknown;
  
  if ([[error domain] isEqualToString:NSURLErrorDomain]) {
    switch (error.code) {
      case NSURLErrorNotConnectedToInternet:
        errorCode = QonversionErrorConnectionFailed; break;
      default:
        errorCode = QonversionErrorInternetConnectionFailed; break;
    }
  } else {
    return error;
  }
  
  return [self errorWithQonverionErrorCode:errorCode];
}

@end
