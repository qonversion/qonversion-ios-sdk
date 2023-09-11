//
//  QONRemoteConfigurationSource.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 30.08.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONRemoteConfigurationAssignmentType) {
  QONRemoteConfigurationAssignmentTypeUnknown = -1,
  QONRemoteConfigurationAssignmentTypeAuto = 0,
  QONRemoteConfigurationAssignmentTypeManual = 1
} NS_SWIFT_NAME(Qonversion.RemoteConfigurationAssignmentType);

typedef NS_ENUM(NSInteger, QONRemoteConfigurationSourceType) {
  QONRemoteConfigurationSourceTypeUnknown = -1,
  QONRemoteConfigurationSourceTypeExperimentControlGroup = 0,
  QONRemoteConfigurationSourceTypeExperimentTreatmentGroup = 1,
  QONRemoteConfigurationSourceTypeRemoteConfiguration = 2
} NS_SWIFT_NAME(Qonversion.RemoteConfigurationSourceType);

NS_SWIFT_NAME(Qonversion.RemoteConfigurationSource)
@interface QONRemoteConfigurationSource : NSObject

/**
 Remote configuration source name. In this field may be the experiment identifier or default remote configuration identifier depends on the source of the payload.
 */
@property (nonatomic, copy, readonly) NSString *identifier;

/**
 Remote configuration source name. In this field may be the experiment name or default remote configuration name depends on the source of the payload..
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 Remote configuration source type
 */
@property (nonatomic, assign, readonly) QONRemoteConfigurationSourceType type;

/**
 Remote config assignment type that indicates how the current payload was assigned to the user.
 */
@property (nonatomic, assign, readonly) QONRemoteConfigurationAssignmentType assignmentType;

@end

NS_ASSUME_NONNULL_END
