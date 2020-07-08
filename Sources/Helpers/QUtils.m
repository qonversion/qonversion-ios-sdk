#import <StoreKit/StoreKit.h>

#import "QUtils.h"
#import "QErrors.h"

@implementation QUtils

+ (BOOL)isEmptyString:(NSString *)string {
  return string == nil || [string isKindOfClass:[NSNull class]] || [string length] == 0;
}

+ (NSError *)errorFromTransactionError:(NSError *)error {
  QonversionError errorCode = QonversionErrorUnknown;
  NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if (error && [[error domain] isEqualToString:SKErrorDomain]) {
    SKErrorCode skErrorCode = error.code;
    
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
  }
  
  return [self errorWithQonverionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorWithQonverionErrorCode:(QonversionError)code
                                userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)dict {
  return [NSError errorWithDomain:QonversionErrorDomain code:code userInfo:dict];
}


+ (NSError *)errorFromURLDomainError:(NSError *)error {
  QonversionError errorCode = QonversionErrorUnknown;
  NSMutableDictionary *userInfo = @{};
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
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
  
  return [self errorWithQonverionErrorCode:errorCode userInfo:userInfo];
}

@end
