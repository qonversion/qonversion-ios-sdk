//
//  QONRemoteConfigMapper.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 12.06.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigMapper.h"
#import "QONRemoteConfig.h"
#import "QONExperiment+Protected.h"
#import "QONExperimentGroup+Protected.h"
#import "QONRemoteConfig+Protected.h"
#import "QONRemoteConfigList+Protected.h"
#import "QONRemoteConfigurationSource+Protected.h"

NSString *const kControlGroupType = @"control";
NSString *const kTreatmentGroupType = @"treatment";

NSString *const kRemoteConfigurationAssignmentTypeAuto = @"auto";
NSString *const kRemoteConfigurationAssignmentTypeManual = @"manual";

NSString *const kRemoteConfigurationSourceTypeControlGroup = @"experiment_control_group";
NSString *const kRemoteConfigurationSourceTypeTreatmentGroup = @"experiment_treatment_group";
NSString *const kRemoteConfigurationSourceTypeRemoteConfiguration = @"remote_configuration";


@interface QONRemoteConfigMapper ()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *groupTypes;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *remoteConfigurationAssignmentTypes;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *remoteConfigurationSourceTypes;

@end

@implementation QONRemoteConfigMapper

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _groupTypes = @{
      kControlGroupType: @(QONExperimentGroupTypeControl),
      kTreatmentGroupType: @(QONExperimentGroupTypeTreatment)
    };
    
    _remoteConfigurationAssignmentTypes = @{
      kRemoteConfigurationAssignmentTypeAuto: @(QONRemoteConfigurationAssignmentTypeAuto),
      kRemoteConfigurationAssignmentTypeManual: @(QONRemoteConfigurationAssignmentTypeManual)
    };
    
    _remoteConfigurationSourceTypes = @{
      kRemoteConfigurationSourceTypeControlGroup: @(QONRemoteConfigurationSourceTypeExperimentControlGroup),
      kRemoteConfigurationSourceTypeTreatmentGroup: @(QONRemoteConfigurationSourceTypeExperimentTreatmentGroup),
      kRemoteConfigurationSourceTypeRemoteConfiguration: @(QONRemoteConfigurationSourceTypeRemoteConfiguration)
    };
  }
  
  return self;
}

- (QONRemoteConfig * _Nullable)mapRemoteConfig:(NSDictionary *)remoteConfigData {
  if (![remoteConfigData isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSDictionary *payload = remoteConfigData[@"payload"];
  NSDictionary *experimentData = remoteConfigData[@"experiment"];
  NSDictionary *remoteConfigurationSourceData = remoteConfigData[@"source"];
  
  QONRemoteConfigurationSource *remoteConfigurationSource = [self mapRemoteConfigurationSource:remoteConfigurationSourceData];
  QONExperiment *experiment = [self mapExperiment:experimentData];
  
  return [[QONRemoteConfig alloc] initWithPayload:payload experiment:experiment source:remoteConfigurationSource];
}

- (QONRemoteConfigList * _Nullable)mapRemoteConfigList:(NSArray *)remoteConfigListData {
  if (![remoteConfigListData isKindOfClass:[NSArray class]]) {
    return nil;
  }
  
  NSMutableArray *remoteConfigs = [NSMutableArray new];
  for (NSDictionary *remoteConfigData in remoteConfigListData) {
    if ([remoteConfigData isKindOfClass:[NSDictionary class]]) {
      QONRemoteConfig *config = [self mapRemoteConfig:remoteConfigData];
      if (config != nil && config.source != nil) {
        [remoteConfigs addObject:config];
      }
    }
  }

  return [[QONRemoteConfigList alloc] initWithRemoteConfigs:remoteConfigs];
}

- (QONExperiment *)mapExperiment:(NSDictionary *)experimentData {
  if (![experimentData isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  
  NSDictionary *experimentGroupData = experimentData[@"group"];
  QONExperimentGroup *group = [self mapExperimentGroup:experimentGroupData];
  if (!group) {
    return nil;
  }
  NSString *experimentId = experimentData[@"uid"];
  NSString *experimentName = experimentData[@"name"];
  
  return [[QONExperiment alloc] initWithIdentifier:experimentId name:experimentName group:group];
}

- (QONRemoteConfigurationSource *)mapRemoteConfigurationSource:(NSDictionary *)remoteConfigurationSourceData {
  if (![remoteConfigurationSourceData isKindOfClass:[NSDictionary class]] || remoteConfigurationSourceData.count == 0) {
    return nil;
  }
  
  NSString *uid = remoteConfigurationSourceData[@"uid"];
  NSString *name = remoteConfigurationSourceData[@"name"];
  NSString *contextKey = remoteConfigurationSourceData[@"context_key"];
  if ([contextKey isEqualToString:@""]) {
    contextKey = nil;
  }

  NSString *typeRawValue = remoteConfigurationSourceData[@"type"];
  QONRemoteConfigurationSourceType type = [self mapRemoteConfigurationSourceTypeFromString:typeRawValue];

  NSString *assignmentTypeRawValue = remoteConfigurationSourceData[@"assignment_type"];
  QONRemoteConfigurationAssignmentType assignmentType = [self mapRemoteConfigurationAssignmentTypeFromString:assignmentTypeRawValue];

  return [[QONRemoteConfigurationSource alloc] initWithIdentifier:uid name:name type:type assignmentType:assignmentType contextKey:contextKey];
}

- (QONExperimentGroup *)mapExperimentGroup:(NSDictionary *)experimentGroupData {
  if (![experimentGroupData isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  
  NSString *groupId = experimentGroupData[@"uid"];
  NSString *groupName = experimentGroupData[@"name"];
  NSString *groupTypeRawValue = experimentGroupData[@"type"];
  QONExperimentGroupType groupType = [self mapGroupTypeFromString:groupTypeRawValue];
  
  return [[QONExperimentGroup alloc] initWithIdentifier:groupId type:groupType name:groupName];
}

- (QONRemoteConfigurationAssignmentType)mapRemoteConfigurationAssignmentTypeFromString:(NSString *)typeString {
  QONRemoteConfigurationAssignmentType type = QONRemoteConfigurationAssignmentTypeUnknown;
  
  NSNumber *typeNumber = self.remoteConfigurationAssignmentTypes[typeString];
  if (typeNumber) {
    type = typeNumber.integerValue;
  }
  
  return type;
}

- (QONRemoteConfigurationSourceType)mapRemoteConfigurationSourceTypeFromString:(NSString *)typeString {
  QONRemoteConfigurationSourceType type = QONRemoteConfigurationSourceTypeUnknown;
  
  NSNumber *typeNumber = self.remoteConfigurationSourceTypes[typeString];
  if (typeNumber) {
    type = typeNumber.integerValue;
  }
  
  return type;
}

- (QONExperimentGroupType)mapGroupTypeFromString:(NSString *)groupTypeString {
  QONExperimentGroupType groupType = QONExperimentGroupTypeUnknown;
  
  NSNumber *groupTypeNumber = self.groupTypes[groupTypeString];
  if (groupTypeNumber) {
    groupType = groupTypeNumber.integerValue;
  }
  
  return groupType;
}

@end
