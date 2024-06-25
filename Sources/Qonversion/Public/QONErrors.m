#import "QONErrors.h"
#import "QNInternalConstants.h"
#import "Qonversion.h"
#import <StoreKit/StoreKit.h>

@implementation QONErrors

+ (NSString *)messageForError:(QONError)error {
  switch (error) {
    case QONErrorIncorrectRequest:
      return @"Request failed.";
    case QONErrorFailedToReceiveData:
      return @"Could not receive data";
    case QONErrorResponseParsingFailed:
      return @"Could not parse response";
    default: return @"Request failed.";
  }
  
  return @"";
}

+ (NSError *)errorWithCode:(QONError)errorCode message:(NSString *)message failureReason:(NSString *)failureReason {
  NSMutableDictionary *info = [NSMutableDictionary new];
  info[NSLocalizedDescriptionKey] = NSLocalizedString(message, nil);
  
  if (failureReason.length > 0) {
    info[NSDebugDescriptionErrorKey] = NSLocalizedString(failureReason, nil);
  }
  
  NSError *error = [NSError errorWithDomain:QonversionErrorDomain code:errorCode userInfo:[info copy]];
  
  return error;
}

+ (NSError *)errorWithCode:(QONError)errorCode message:(NSString *)message {
  NSMutableDictionary *info = [NSMutableDictionary new];
  info[NSLocalizedDescriptionKey] = NSLocalizedString(message, nil);
  
  NSError *error = [NSError errorWithDomain:QonversionErrorDomain code:errorCode userInfo:[info copy]];
  
  return error;
}

+ (NSError *)errorWithQONErrorCode:(QONError)errorCode {
  return [self errorWithQonversionErrorCode:errorCode userInfo:nil];
}

+ (NSError *)errorWithCode:(QONError)errorCode {
  NSDictionary *info = @{NSLocalizedDescriptionKey: NSLocalizedString([self messageForError:errorCode], nil)};
  
  return [self errorWithQonversionErrorCode:QONErrorInternalError userInfo:info];
}

+ (NSError *)deferredTransactionError {
  NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
  userInfo[NSLocalizedDescriptionKey] = @"The transaction is deferred";
  
  return [self errorWithQonversionErrorCode:QONErrorStorePurchasePending userInfo:[userInfo copy]];
}

+ (NSError *)errorFromTransactionError:(NSError *)error {
  QONError errorCode = QONErrorUnknown;
  NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if ([[error domain] isEqualToString:NSURLErrorDomain]) {
    errorCode = QONErrorNetworkConnectionFailed;
  }
  
  if ([[error domain] isEqualToString:SKErrorDomain]) {
    SKErrorCode skErrorCode = error.code;
    
      switch (skErrorCode) {
        case SKErrorUnknown:
          errorCode = QONErrorUnknown; break;
        case SKErrorClientInvalid:
          errorCode = QONErrorClientInvalid; break;
        case SKErrorPaymentCancelled:
          errorCode = QONErrorPurchaseCanceled; break;
        case SKErrorPaymentNotAllowed:
          errorCode = QONErrorPaymentNotAllowed; break;
        case SKErrorPaymentInvalid:
          errorCode = QONErrorPaymentInvalid; break;
        // Belowe codes available on different iOS
        case 5:
          errorCode = QONErrorStoreProductNotAvailable; break;
        case 6: // SKErrorCloudServicePermissionDenied
          errorCode = QONErrorCloudServicePermissionDenied; break;
        case 7: // SKErrorCloudServiceNetworkConnectionFailed
          errorCode = QONErrorCloudServiceNetworkConnectionFailed; break;
        case 8: // SKErrorCloudServiceRevoked
          errorCode = QONErrorCloudServiceRevoked; break;
        case 9: // SKErrorPrivacyAcknowledgementRequired
          errorCode = QONErrorPrivacyAcknowledgementRequired; break;
        case 10: // SKErrorUnauthorizedRequestData
          errorCode = QONErrorUnauthorizedRequestData; break;
        default:
          errorCode = QONErrorUnknown; break;
      }
  }
  
  userInfo[NSHelpAnchorErrorKey] = [self helpAnchorForErrorCode:errorCode];
  
  return [self errorWithQonversionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorFromURLDomainError:(NSError *)error {
  QONError errorCode = QONErrorUnknown;
  NSMutableDictionary *userInfo = [NSMutableDictionary new];
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if ([[error domain] isEqualToString:NSURLErrorDomain]) {
    errorCode = QONErrorNetworkConnectionFailed;

    userInfo[NSHelpAnchorErrorKey] = [self helpAnchorForErrorCode:errorCode];
  } else {
    return error;
  }
  
  return [self errorWithQonversionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorWithQonversionErrorCode:(QONError)code
                                userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)dict {
  return [NSError errorWithDomain:QonversionErrorDomain code:code userInfo:dict];
}

+ (NSString *)helpAnchorForErrorCode:(QONError)errorCode {
  NSString *result = @"";
  
  switch (errorCode) {
    case QONErrorPurchaseCanceled:
      result = @"User canceled the request"; break;
    
    case QONErrorProductNotFound:
      result = @"The requested product not found. See more info about this error in the documentation https://documentation.qonversion.io/docs/troubleshooting#product-not-found-error"; break;
    
    case QONErrorClientInvalid:
      result = @"Client is not allowed to issue the request"; break;
      
    case QONErrorPaymentInvalid:
      result = @"Purchase identifier was invalid"; break;
      
    case QONErrorPaymentNotAllowed:
      result = @"This device is not allowed to make the payment"; break;

    case QONErrorStoreProductNotAvailable:
      result = @"Product is not available in the current storefront or Products on Qonversion Dashboard configured with wrong store product identifier"; break;
      
    case QONErrorCloudServicePermissionDenied:
      result = @"User has not allowed access to cloud service information"; break;

    case QONErrorCloudServiceRevoked:
      result = @"User has revoked permission to use this cloud service"; break;
      
    case QONErrorPrivacyAcknowledgementRequired:
      result = @"User needs to acknowledge Apple's privacy policy"; break;
      
    case QONErrorUnauthorizedRequestData:
      result = @"App is attempting to use SKPayment's requestData property, but does not have the appropriate entitlement"; break;
     
    case QONErrorNetworkConnectionFailed:
      result = @"There was a network issue. Please make sure that the Internet connection is available on the device"; break;

    case QONErrorInternalError:
      result = @"Internal error occurred"; break;
      
    default:
      break;
  }
  
  result = [NSString stringWithFormat:@"%@\nCheck more info about errors here: https://documentation.qonversion.io/docs/troubleshooting", result];
  
  return result;
}

@end
