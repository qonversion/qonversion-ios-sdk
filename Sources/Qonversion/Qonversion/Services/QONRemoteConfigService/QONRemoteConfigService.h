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

- (void)loadRemoteConfig:(NSString * _Nullable)contextKey completion:(QONRemoteConfigCompletionHandler)completion;
- (void)loadRemoteConfigList:(QONRemoteConfigListCompletionHandler)completion;
- (void)loadRemoteConfigList:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion;
- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion;
- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion;
- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfiguration completion:(QONRemoteConfigurationAttachCompletionHandler)completion;
- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfiguration completion:(QONRemoteConfigurationAttachCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
