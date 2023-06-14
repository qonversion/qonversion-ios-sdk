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
  NSDictionary *payload = remoteConfigData[@"Payload"];
  NSDictionary *experimentData = remoteConfigData[@"Experiment"];
  QONExperiment *experiment = [self mapExperiment:experimentData];
  
  return [[QONRemoteConfig alloc] initWithPayload:payload experiment:experiment];
}

- (QONExperiment *)mapExperiment:(NSDictionary *)experimentData {
  if (![experimentData isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  NSDictionary *experimentGroupData = experimentData[@"Group"];
  QONExperimentGroup *group = [self mapExperimentGroup:experimentGroupData];
  if (!group) {
    return nil;
  }
  NSString *experimentId = experimentData[@"Uid"];
  NSString *experimentName = experimentData[@"Name"];
  
  return [[QONExperiment alloc] initWithIdentifier:experimentId name:experimentName group:group];
}

- (QONExperimentGroup *)mapExperimentGroup:(NSDictionary *)experimentGroupData {
  if (![experimentGroupData isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  
  NSString *groupId = experimentGroupData[@"Uid"];
  NSString *groupName = experimentGroupData[@"Name"];
  NSString *groupTypeRawValue = experimentGroupData[@"Type"];
  QONExperimentGroupType *groupType = [self mapGroupTypeFromString:groupTypeRawValue];
  
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
