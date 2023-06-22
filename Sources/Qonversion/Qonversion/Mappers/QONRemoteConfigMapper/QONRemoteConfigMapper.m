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

NSString *const kControlGroupType = @"control";
NSString *const kTreatmentGroupType = @"treatment";

@interface QONRemoteConfigMapper ()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *groupTypes;

@end

@implementation QONRemoteConfigMapper

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _groupTypes = @{
      kControlGroupType: @(QONExperimentGroupTypeControl),
      kTreatmentGroupType: @(QONExperimentGroupTypeTreatment)
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
  QONExperiment *experiment = [self mapExperiment:experimentData];
  
  return [[QONRemoteConfig alloc] initWithPayload:payload experiment:experiment];
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

- (QONExperimentGroupType)mapGroupTypeFromString:(NSString *)groupTypeString {
  QONExperimentGroupType groupType = QONExperimentGroupTypeUnknown;
  
  NSNumber *groupTypeNumber = self.groupTypes[groupTypeString];
  if (groupTypeNumber) {
    groupType = groupTypeNumber.integerValue;
  }
  
  return groupType;
}

@end
