//
//  QNErrorsMapper.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 22.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNErrorsMapper.h"
#import "QONErrors.h"

static NSString *const kDefaultErrorMessage = @"Internal error occurred";

@interface QNErrorsMapper ()

@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *errorsMap;

@end

@implementation QNErrorsMapper

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _errorsMap = @{@(QONErrorProjectConfigError) : @"The project is not configured or configured incorrectly in the Qonversion Dashboard.",
                   @(QONErrorInvalidStoreCredentials) : @"Please check provided Store keys in the Qonversion Dashboard.",
                   @(QONErrorReceiptValidationError) : @"Provided receipt can't be validated. Please check the details here: https://documentation.qonversion.io/docs/troubleshooting#receipt-validation-error"
    };
  }
  
  return self;
}

- (NSError *)errorFromRequestResult:(NSDictionary *)result {
  if (![result isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  
  if ([result[@"data"] isKindOfClass:[NSDictionary class]]) {
    return [self mapErrorFromData:result];
  } else if ([result[@"error"] isKindOfClass:[NSDictionary class]]) {
    return [self mapError:result];
  }
  
  return nil;
}

- (NSError * _Nullable)mapError:(NSDictionary *)result {
  NSDictionary *errorDict = result[@"error"];
  NSString *errorMessage = errorDict[@"message"] ?: kDefaultErrorMessage;
  
  NSError *error = [QONErrors errorWithCode:QONErrorBackendError message:errorMessage failureReason:nil];
  
  return error;
}

- (NSError * _Nullable)mapErrorFromData:(NSDictionary *)result {
  BOOL isSuccessRequest = [result[@"success"] boolValue];
  
  if (isSuccessRequest) {
    return nil;
  }
  
  NSDictionary *data = result[@"data"];
  NSNumber *codeNumber = data[@"code"];
  
  if (!codeNumber) {
    return [QONErrors errorWithCode:QONErrorBackendError message:kDefaultErrorMessage failureReason:nil];
  }
  
  QONError errorType = [self errorTypeFromCode:codeNumber];
  NSString *apiErrorMessage = data[@"message"];
  NSString *failureReason = [self messageForErrorType:errorType];
  NSString *additionalMessage = [NSString stringWithFormat:@"Internal error code: %li.", (long)codeNumber.integerValue];
  
  if (failureReason.length > 0) {
    additionalMessage = [NSString stringWithFormat:@"%@\n%@", additionalMessage, failureReason];
  }
  
  NSError *error = [QONErrors errorWithCode:errorType message:apiErrorMessage failureReason:additionalMessage];
  
  return error;
}

- (NSString *)messageForErrorType:(QONError)errorType {
  return self.errorsMap[@(errorType)];
}

- (QONError)errorTypeFromCode:(NSNumber *)errorCode {
  QONError type = QONErrorBackendError;
  
  switch (errorCode.integerValue) {
    case 10000:
    case 10001:
    case 10007:
    case 10009:
    case 20000:
    case 20009:
    case 20015:
    case 20099:
    case 20300:
    case 20303:
    case 20200:
      type = QONErrorBackendError;
      break;
      
    case 10002:
    case 10003:
      type = QONErrorInvalidCredentials;
      break;
      
    case 10004:
    case 10005:
    case 20014:
      type = QONErrorInvalidClientUID;
      break;
      
    case 10006:
      type = QONErrorUnknownClientPlatform;
      break;
      
    case 10008:
      type = QONErrorFraudPurchase;
      break;
      
    case 20005:
      type = QONErrorFeatureNotSupported;
      break;
      
    case 20006:
    case 20007:
    case 20109:
    case 20199:
      type = QONErrorAppleStoreError;
      break;
      
    case 20008:
    case 20010:
      type = QONErrorPurchaseInvalid;
      break;
      
    case 20011:
    case 20012:
    case 20013:
      type = QONErrorProjectConfigError;
      break;
      
    case 20104:
      type = QONErrorInvalidStoreCredentials;
      break;
      
    case 20102:
    case 20103:
    case 20105:
    case 20110:
    case 20100:
    case 20107:
    case 20108:
    case 21099:
      type = QONErrorReceiptValidationError;
      break;
      
    default:
      break;
      
  }
  
  return type;
}

@end
