#import <StoreKit/StoreKit.h>

#import "QNUtils.h"
#import "QNErrors.h"

@implementation QNUtils

+ (BOOL)isEmptyString:(NSString *)string {
  return string == nil || [string isKindOfClass:[NSNull class]] || [string length] == 0;
}

+ (NSError *)errorFromTransactionError:(NSError *)error {
  QNError errorCode = QNErrorUnknown;
  NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if (error && [[error domain] isEqualToString:SKErrorDomain]) {
    SKErrorCode skErrorCode = error.code;
    
      switch (skErrorCode) {
        case SKErrorUnknown:
          errorCode = QNErrorUnknown; break;
        case SKErrorPaymentCancelled:
          errorCode = QNErrorCancelled; break;
        case SKErrorStoreProductNotAvailable:
          errorCode = QNErrorStoreProductNotAvailable; break;
        case SKErrorPaymentNotAllowed:
          errorCode = QNErrorPaymentNotAllowed; break;
        case SKErrorPaymentInvalid:
          errorCode = QNErrorPaymentInvalid; break;
        // Belowe codes available on different iOS
        case 6: // SKErrorCloudServicePermissionDenied
          errorCode = QNErrorCloudServicePermissionDenied;
        case 7: // SKErrorCloudServiceNetworkConnectionFailed
          errorCode = QNErrorConnectionFailed; break;
        case 8: // SKErrorCloudServiceRevoked
          errorCode = QNErrorCloudServiceRevoked; break;
        case 9: // SKErrorPrivacyAcknowledgementRequired
          errorCode = QNErrorPrivacyAcknowledgementRequired; break;
        case 10: // SKErrorUnauthorizedRequestData
          errorCode = QNErrorUnauthorizedRequestData; break;
      }
  }
  
  return [self errorWithQonverionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorWithQonverionErrorCode:(QNError)code
                                userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)dict {
  return [NSError errorWithDomain:QNErrorDomain code:code userInfo:dict];
}


+ (NSError *)errorFromURLDomainError:(NSError *)error {
  QNError errorCode = QNErrorUnknown;
  NSMutableDictionary *userInfo = @{};
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if ([[error domain] isEqualToString:NSURLErrorDomain]) {
    switch (error.code) {
      case NSURLErrorNotConnectedToInternet:
        errorCode = QNErrorConnectionFailed; break;
      default:
        errorCode = QNErrorInternetConnectionFailed; break;
    }
  } else {
    return error;
  }
  
  return [self errorWithQonverionErrorCode:errorCode userInfo:userInfo];
}

@end
