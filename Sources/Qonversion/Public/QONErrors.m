#import "QONErrors.h"
#import "QNInternalConstants.h"
#import "Qonversion.h"
#import <StoreKit/StoreKit.h>

@implementation QONErrors

+ (NSString *)messageForError:(QONErrorCode)error {
  switch (error) {
    case QONErrorCodeIncorrectRequest:
      return @"Request failed.";
    case QONErrorCodeFailedToReceiveData:
      return @"Could not receive data";
    case QONErrorCodeResponseParsingFailed:
      return @"Could not parse response";
    default: return @"Request failed.";
  }
  
  return @"";
}

+ (NSError *)errorWithCode:(QONErrorCode)errorCode message:(NSString *)message failureReason:(NSString *)failureReason {
  NSMutableDictionary *info = [NSMutableDictionary new];
  info[NSLocalizedDescriptionKey] = NSLocalizedString(message, nil);
  
  if (failureReason.length > 0) {
    info[NSDebugDescriptionErrorKey] = NSLocalizedString(failureReason, nil);
  }
  
  NSError *error = [NSError errorWithDomain:QonversionErrorDomain code:errorCode userInfo:[info copy]];
  
  return error;
}

+ (NSError *)errorWithCode:(QONErrorCode)errorCode message:(NSString *)message {
  NSMutableDictionary *info = [NSMutableDictionary new];
  info[NSLocalizedDescriptionKey] = NSLocalizedString(message, nil);
  
  NSError *error = [NSError errorWithDomain:QonversionErrorDomain code:errorCode userInfo:[info copy]];
  
  return error;
}

+ (NSError *)errorWithQONErrorCode:(QONErrorCode)errorCode {
  return [self errorWithQonversionErrorCode:errorCode userInfo:nil];
}

+ (NSError *)internalErrorWithCode:(QONErrorCode)errorCode {
  NSDictionary *info = @{NSLocalizedDescriptionKey: NSLocalizedString([self messageForError:errorCode], nil)};
  
  return [self errorWithQonversionErrorCode:QONErrorCodeInternalError userInfo:info];
}

+ (NSError *)deferredTransactionError {
  NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
  userInfo[NSLocalizedDescriptionKey] = @"The transaction is deferred";
  
  return [self errorWithQonversionErrorCode:QONErrorCodePurchasePending userInfo:[userInfo copy]];
}

+ (NSError *)errorFromTransactionError:(NSError *)error {
  QONErrorCode errorCode = QONErrorCodeUnknown;
  NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if ([[error domain] isEqualToString:NSURLErrorDomain]) {
    errorCode = QONErrorCodeNetworkConnectionFailed;
  }
  
  if ([[error domain] isEqualToString:SKErrorDomain]) {
    SKErrorCode skErrorCode = error.code;
    
      switch (skErrorCode) {
        case SKErrorUnknown:
          errorCode = QONErrorCodeUnknown; break;
        case SKErrorClientInvalid:
          errorCode = QONErrorCodeClientInvalid; break;
        case SKErrorPaymentCancelled:
          errorCode = QONErrorCodePurchaseCanceled; break;
        case SKErrorPaymentNotAllowed:
          errorCode = QONErrorCodePaymentNotAllowed; break;
        case SKErrorPaymentInvalid:
          errorCode = QONErrorCodePaymentInvalid; break;
        // Belowe codes available on different iOS
        case 5:
          errorCode = QONErrorCodeStoreProductNotAvailable; break;
        case 6: // SKErrorCloudServicePermissionDenied
          errorCode = QONErrorCodeCloudServicePermissionDenied; break;
        case 7: // SKErrorCloudServiceNetworkConnectionFailed
          errorCode = QONErrorCodeCloudServiceNetworkConnectionFailed; break;
        case 8: // SKErrorCloudServiceRevoked
          errorCode = QONErrorCodeCloudServiceRevoked; break;
        case 9: // SKErrorPrivacyAcknowledgementRequired
          errorCode = QONErrorCodePrivacyAcknowledgementRequired; break;
        case 10: // SKErrorUnauthorizedRequestData
          errorCode = QONErrorCodeUnauthorizedRequestData; break;
        default:
          errorCode = QONErrorCodeUnknown; break;
      }
  }
  
  userInfo[NSHelpAnchorErrorKey] = [self helpAnchorForErrorCode:errorCode];
  
  return [self errorWithQonversionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorFromURLDomainError:(NSError *)error {
  QONErrorCode errorCode = QONErrorCodeUnknown;
  NSMutableDictionary *userInfo = [NSMutableDictionary new];
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if ([[error domain] isEqualToString:NSURLErrorDomain]) {
    errorCode = QONErrorCodeNetworkConnectionFailed;

    userInfo[NSHelpAnchorErrorKey] = [self helpAnchorForErrorCode:errorCode];
  } else {
    return error;
  }
  
  return [self errorWithQonversionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorWithQonversionErrorCode:(QONErrorCode)code
                                userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)dict {
  return [NSError errorWithDomain:QonversionErrorDomain code:code userInfo:dict];
}

+ (NSString *)helpAnchorForErrorCode:(QONErrorCode)errorCode {
  NSString *result = @"";
  
  switch (errorCode) {
    case QONErrorCodePurchaseCanceled:
      result = @"User canceled the request"; break;
    
    case QONErrorCodeProductNotFound:
      result = @"The requested product not found. See more info about this error in the documentation https://documentation.qonversion.io/docs/troubleshooting#product-not-found-error"; break;
    
    case QONErrorCodeClientInvalid:
      result = @"Client is not allowed to issue the request"; break;
      
    case QONErrorCodePaymentInvalid:
      result = @"Purchase identifier was invalid"; break;
      
    case QONErrorCodePaymentNotAllowed:
      result = @"This device is not allowed to make the payment"; break;

    case QONErrorCodeStoreProductNotAvailable:
      result = @"Product is not available in the current storefront or Products on Qonversion Dashboard configured with wrong store product identifier"; break;
      
    case QONErrorCodeCloudServicePermissionDenied:
      result = @"User has not allowed access to cloud service information"; break;

    case QONErrorCodeCloudServiceRevoked:
      result = @"User has revoked permission to use this cloud service"; break;
      
    case QONErrorCodePrivacyAcknowledgementRequired:
      result = @"User needs to acknowledge Apple's privacy policy"; break;
      
    case QONErrorCodeUnauthorizedRequestData:
      result = @"App is attempting to use SKPayment's requestData property, but does not have the appropriate entitlement"; break;
     
    case QONErrorCodeNetworkConnectionFailed:
      result = @"There was a network issue. Please make sure that the Internet connection is available on the device"; break;

    case QONErrorCodeInternalError:
      result = @"Internal error occurred"; break;
      
    default:
      break;
  }
  
  result = [NSString stringWithFormat:@"%@\nCheck more info about errors here: https://documentation.qonversion.io/docs/troubleshooting", result];
  
  return result;
}

@end
