//
//  QONRemoteConfigService.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"
#import "QONExperiment.h"

@class QNAPIClient, QONRemoteConfigMapper;

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigService : NSObject

@property (nonatomic, strong) QNAPIClient *apiClient;
@property (nonatomic, strong) QONRemoteConfigMapper *mapper;

- (void)loadRemoteConfig:(QONRemoteConfigCompletionHandler)completion;
- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion;
- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
