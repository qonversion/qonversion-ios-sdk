//
//  QONRemoteConfigurationSource.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 30.08.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigurationSource.h"

@implementation QONRemoteConfigurationSource

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                              type:(QONRemoteConfigurationSourceType)type
                    assignmentType:(QONRemoteConfigurationAssignmentType)assignmentType
                        contextKey:(NSString * _Nullable)contextKey {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _name = name;
    _type = type;
    _assignmentType = assignmentType;
    _contextKey = contextKey;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  [description appendFormat:@"identifier=%@\n", self.identifier];
  [description appendFormat:@"name=%@\n", self.name];
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  [description appendFormat:@"assignmentType=%@ (enum value = %li),\n", [self prettyAssignmentType], (long) self.assignmentType];
  [description appendFormat:@"contextKey=%@\n", self.contextKey];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyAssignmentType {
  NSString *result;
  
  switch (self.assignmentType) {
    case QONRemoteConfigurationAssignmentTypeAuto:
      result = @"auto"; break;
    
    case QONRemoteConfigurationAssignmentTypeManual:
      result = @"manual"; break;
      
    default:
      result = @"unknown"; break;
  }
  
  return result;
}

- (NSString *)prettyType {
  NSString *result;
  
  switch (self.type) {
    case QONRemoteConfigurationSourceTypeRemoteConfiguration:
      result = @"remote configuration"; break;
    
    case QONRemoteConfigurationSourceTypeExperimentControlGroup:
      result = @"experiment control group"; break;
      
    case QONRemoteConfigurationSourceTypeExperimentTreatmentGroup:
      result = @"experiment treatment group"; break;
      
    default:
      result = @"unknown"; break;
  }
  
  return result;
}

@end
