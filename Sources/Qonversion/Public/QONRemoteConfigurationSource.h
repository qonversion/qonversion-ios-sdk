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
 Remote configuration source name. Can be the experiment identifier or default remote configuration identifier, depending on the payload's source.
 */
@property (nonatomic, copy, readonly) NSString *identifier;

/**
 Remote configuration source name. Can be the experiment name or default remote configuration name, depending on the payload's source.
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

/**
 Remote configuration context key. Empty string if not specified.
 */
@property (nonatomic, copy, readonly) NSString * _Nullable contextKey;

@end

NS_ASSUME_NONNULL_END
