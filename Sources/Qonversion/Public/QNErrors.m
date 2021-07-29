#import "QNErrors.h"
#import <StoreKit/StoreKit.h>

@implementation QNErrors

+ (NSString *)messageForError:(QNAPIError)error {
  switch (error) {
    case QNAPIErrorIncorrectRequest:
      return @"Request failed.";
    case QNAPIErrorFailedReceiveData:
      return @"Could not receive data";
    case QNAPIErrorFailedParseResponse:
      return @"Could not parse response";
    default: return @"Request failed.";
  }
  
  return @"";
}

+ (NSError *)errorWithCode:(QNAPIError)errorCode message:(NSString *)message failureReason:(NSString *)failureReason {
  NSMutableDictionary *info = [NSMutableDictionary new];
  info[NSLocalizedDescriptionKey] = NSLocalizedString(message, nil);
  
  if (failureReason.length > 0) {
    info[NSDebugDescriptionErrorKey] = NSLocalizedString(failureReason, nil);
  }
  
  NSError *error = [NSError errorWithDomain:keyQNAPIErrorDomain code:errorCode userInfo:[info copy]];
  
  return error;
}

+ (NSError *)errorWithQNErrorCode:(QNError)errorCode {
  return [self errorWithQonversionErrorCode:errorCode userInfo:nil];
}

+ (NSError *)errorWithCode:(QNAPIError)errorCode {
  NSDictionary *info = @{NSLocalizedDescriptionKey: NSLocalizedString([self messageForError:errorCode], nil)};
  
  return [self errorWithQonversionErrorCode:QNErrorInternalError userInfo:info];
}

+ (NSError *)deferredTransactionError {
  NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
  userInfo[NSLocalizedDescriptionKey] = @"The transaction is deferred";
  
  return [self errorWithQonversionErrorCode:QNErrorStorePaymentDeferred userInfo:[userInfo copy]];
}

+ (NSError *)errorFromTransactionError:(NSError *)error {
  QNError errorCode = QNErrorUnknown;
  NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if ([[error domain] isEqualToString:NSURLErrorDomain]) {
    switch (error.code) {
      case NSURLErrorNotConnectedToInternet:
        errorCode = QNErrorConnectionFailed; break;
      default:
        errorCode = QNErrorInternetConnectionFailed; break;
    }
  }
  
  if (error && [[error domain] isEqualToString:SKErrorDomain]) {
    SKErrorCode skErrorCode = error.code;
    
      switch (skErrorCode) {
        case SKErrorUnknown:
          errorCode = QNErrorUnknown; break;
        case SKErrorClientInvalid:
          errorCode = QNErrorClientInvalid; break;
        case SKErrorPaymentCancelled:
          errorCode = QNErrorCancelled; break;
        case SKErrorPaymentNotAllowed:
          errorCode = QNErrorPaymentNotAllowed; break;
        case SKErrorPaymentInvalid:
          errorCode = QNErrorPaymentInvalid; break;
        // Belowe codes available on different iOS
        case 5:
          errorCode = QNErrorStoreProductNotAvailable; break;
        case 6: // SKErrorCloudServicePermissionDenied
          errorCode = QNErrorCloudServicePermissionDenied; break;
        case 7: // SKErrorCloudServiceNetworkConnectionFailed
          errorCode = QNErrorConnectionFailed; break;
        case 8: // SKErrorCloudServiceRevoked
          errorCode = QNErrorCloudServiceRevoked; break;
        case 9: // SKErrorPrivacyAcknowledgementRequired
          errorCode = QNErrorPrivacyAcknowledgementRequired; break;
        case 10: // SKErrorUnauthorizedRequestData
          errorCode = QNErrorUnauthorizedRequestData; break;
        default:
          errorCode = QNErrorUnknown; break;
      }
  }
  
  userInfo[NSHelpAnchorErrorKey] = [self helpAnchorForErrorCode:errorCode];
  
  return [self errorWithQonversionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorFromURLDomainError:(NSError *)error {
  QNError errorCode = QNErrorUnknown;
  NSMutableDictionary *userInfo = [NSMutableDictionary new];
  userInfo[NSLocalizedDescriptionKey] = error.localizedDescription ?: @"";
  
  if ([[error domain] isEqualToString:NSURLErrorDomain]) {
    switch (error.code) {
      case NSURLErrorNotConnectedToInternet:
        errorCode = QNErrorConnectionFailed; break;
      default:
        errorCode = QNErrorInternetConnectionFailed; break;
    }
    
    userInfo[NSHelpAnchorErrorKey] = [self helpAnchorForErrorCode:errorCode];
  } else {
    return error;
  }
  
  return [self errorWithQonversionErrorCode:errorCode userInfo:userInfo];
}

+ (NSError *)errorWithQonversionErrorCode:(QNError)code
                                userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)dict {
  return [NSError errorWithDomain:keyQNErrorDomain code:code userInfo:dict];
}

+ (NSString *)helpAnchorForErrorCode:(QNError)errorCode {
  NSString *result = @"";
  
  switch (errorCode) {
    case QNErrorCancelled:
      result = @"User cancelled the request"; break;
    
    case QNErrorProductNotFound:
      result = @"Requested product not found. See more info about this error in documentation https://documentation.qonversion.io/docs/troubleshooting#1-product-not-found-error"; break;
    
    case QNErrorClientInvalid:
      result = @"Client is not allowed to issue the request"; break;
      
    case QNErrorPaymentInvalid:
      result = @"Purchase identifier was invalid"; break;
      
    case QNErrorPaymentNotAllowed:
      result = @"This device is not allowed to make the payment"; break;
      
    case QNErrorStoreFailed:
      result = @"Apple Store didn't process the request"; break;
      
    case QNErrorStoreProductNotAvailable:
      result = @"Product is not available in the current storefront or Products on Qonversion Dashboard configured with wrong store product identifier"; break;
      
    case QNErrorCloudServicePermissionDenied:
      result = @"User has not allowed access to cloud service information"; break;
      
    case QNErrorCloudServiceNetworkConnectionFailed:
      result = @"The device could not connect to the network"; break;
      
    case QNErrorCloudServiceRevoked:
      result = @"User has revoked permission to use this cloud service"; break;
      
    case QNErrorPrivacyAcknowledgementRequired:
      result = @"User needs to acknowledge Apple's privacy policy"; break;
      
    case QNErrorUnauthorizedRequestData:
      result = @"App is attempting to use SKPayment's requestData property, but does not have the appropriate entitlement"; break;
     
    case QNErrorIncorrectSharedSecret:
      result = @"Provided shared secret is incorrect, validation unavailable. See more info in documentation https://documentation.qonversion.io/docs/app-specific-shared-secret"; break;
      
    case QNErrorConnectionFailed:
      result = @"Failed to connect to Qonversion Backend"; break;
      
    case QNErrorInternetConnectionFailed:
      result = @"Other URL Session errors of NSURLErrorDomain enum"; break;
      
    case QNErrorDataFailed:
      result = @"Network data error"; break;
      
    case QNErrorInternalError:
      result = @"Internal error occurred"; break;
      
    default:
      break;
  }
  
  result = [NSString stringWithFormat:@"%@\nCheck more info about errors here: https://documentation.qonversion.io/docs/troubleshooting", result];
  
  return result;
}

@end
