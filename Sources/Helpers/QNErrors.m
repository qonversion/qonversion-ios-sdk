#import "QNErrors.h"
#import <StoreKit/StoreKit.h>

@implementation QNErrors

+ (NSString *)messageForError:(QNAPIError)error {
  switch (error) {
    case QNAPIErrorIncorrectRequest:
      return @"Request failed. ";
    case QNAPIErrorFailedReceiveData:
      return @"Could not receive data";
    case QNAPIErrorFailedParseResponse:
      return @"Could not parse response";
  }
  
  return @"";
}

+ (NSError *)errorWithQNErrorCode:(QNError)errorCode {
  return [self errorWithQonversionErrorCode:errorCode userInfo:nil];
}

+ (NSError *)errorWithCode:(QNAPIError)errorCode  {
  NSDictionary *info = @{NSLocalizedDescriptionKey: NSLocalizedString([self messageForError:errorCode], nil)};
  
  return [self errorWithQonversionErrorCode:QNErrorInternalError userInfo:info];
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
  
  return [self errorWithQonversionErrorCode:errorCode userInfo:userInfo];
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
  
  return [self errorWithQonversionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorWithQonversionErrorCode:(QNError)code
                                userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)dict {
  return [NSError errorWithDomain:keyQNErrorDomain code:code userInfo:dict];
}

@end
