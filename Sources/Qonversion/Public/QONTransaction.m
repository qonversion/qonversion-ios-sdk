//
//  QONTransaction.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.12.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONTransaction.h"

@implementation QONTransaction

- (instancetype)initWithOriginalTransactionId:(NSString *)originalTransactionId
                                transactionId:(NSString *)transactionId
                                    offerCode:(NSString *)offerCode
                              transactionDate:(NSDate *)transactionDate
                               expirationDate:(NSDate *)expirationDate
                    transactionRevocationDate:(NSDate *)transactionRevocationDate
                                  environment:(QONTransactionEnvironment)environment
                                ownershipType:(QONTransactionOwnershipType)ownershipType
                                         type:(QONTransactionType)type {
  self = [super init];
  
  if (self) {
    _originalTransactionId = originalTransactionId;
    _transactionId = transactionId;
    _offerCode = offerCode;
    _transactionDate = transactionDate;
    _expirationDate = expirationDate;
    _transactionRevocationDate = transactionRevocationDate;
    _environment = environment;
    _ownershipType = ownershipType;
    _type = type;
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _originalTransactionId = [coder decodeObjectForKey:NSStringFromSelector(@selector(originalTransactionId))];
    _transactionId = [coder decodeObjectForKey:NSStringFromSelector(@selector(transactionId))];
    _offerCode = [coder decodeObjectForKey:NSStringFromSelector(@selector(offerCode))];
    _transactionDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(transactionDate))];
    _expirationDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(expirationDate))];
    _transactionRevocationDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(transactionRevocationDate))];
    _environment = [coder decodeIntegerForKey:NSStringFromSelector(@selector(environment))];
    _ownershipType = [coder decodeIntegerForKey:NSStringFromSelector(@selector(ownershipType))];
    _type = [coder decodeIntegerForKey:NSStringFromSelector(@selector(type))];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_originalTransactionId forKey:NSStringFromSelector(@selector(originalTransactionId))];
  [coder encodeObject:_transactionId forKey:NSStringFromSelector(@selector(transactionId))];
  [coder encodeObject:_offerCode forKey:NSStringFromSelector(@selector(offerCode))];
  [coder encodeObject:_transactionDate forKey:NSStringFromSelector(@selector(transactionDate))];
  [coder encodeObject:_expirationDate forKey:NSStringFromSelector(@selector(expirationDate))];
  [coder encodeObject:_transactionRevocationDate forKey:NSStringFromSelector(@selector(transactionRevocationDate))];
  [coder encodeInteger:_environment forKey:NSStringFromSelector(@selector(environment))];
  [coder encodeInteger:_ownershipType forKey:NSStringFromSelector(@selector(ownershipType))];
  [coder encodeInteger:_type forKey:NSStringFromSelector(@selector(type))];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  [description appendFormat:@"originalTransactionId=%@,\n", self.originalTransactionId];
  [description appendFormat:@"transactionId=%@,\n", self.transactionId];
  [description appendFormat:@"offerCode=%@,\n", self.offerCode];
  [description appendFormat:@"transactionDate=%@,\n", self.transactionDate];
  [description appendFormat:@"expirationDate=%@,\n", self.expirationDate];
  [description appendFormat:@"transactionRevocationDate=%@,\n", self.transactionRevocationDate];
  [description appendFormat:@"environment=%@ (enum value = %li),\n", [self prettyEnvironment], (long) self.environment];
  [description appendFormat:@"ownershipType=%@ (enum value = %li),\n", [self prettyOwnershipType], (long) self.ownershipType];
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyEnvironment {
  NSString *result = @"production";
  
  switch (self.environment) {
    case QONTransactionEnvironmentSandbox:
      result = @"sandbox"; break;
    
    case QONTransactionEnvironmentProduction:
      result = @"production"; break;
    default:
      break;
  }
  
  return result;
}

- (NSString *)prettyOwnershipType {
  NSString *result = @"owner";
  
  switch (self.ownershipType) {
    case QONTransactionOwnershipTypeOwner:
      result = @"owner"; break;
    
    case QONTransactionOwnershipTypeFamilySharing:
      result = @"family sharing"; break;
    default:
      break;
  }
  
  return result;
}

- (NSString *)prettyType {
  NSString *result = @"subscription renewed";
  
  switch (self.type) {
    case QONTransactionTypeSubscriptionStarted:
      result = @"subscription started"; break;
    
    case QONTransactionTypeSubscriptionRenewed:
      result = @"subscription renewed"; break;
      
    case QONTransactionTypeTrialStarted:
      result = @"trial started"; break;
      
    case QONTransactionTypeIntroStarted:
      result = @"intro started"; break;
      
    case QONTransactionTypeIntroRenewed:
      result = @"intro renewed"; break;
      
    case QONTransactionTypeNonConsumablePurchase:
      result = @"non-consumable purchase"; break;
    default:
      break;
  }
  
  return result;
}

@end
