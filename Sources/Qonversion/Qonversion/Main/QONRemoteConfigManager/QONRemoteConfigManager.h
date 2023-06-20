//
//  QONRemoteConfigManager.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"
#import "QONExperiment.h"

@class QONRemoteConfigService, QNProductCenterManager;

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigManager : NSObject

@property (nonatomic, strong) QONRemoteConfigService *remoteConfigService;
@property (nonatomic, strong) QNProductCenterManager *productCenterManager;

- (void)userChangingRequestsFailedWithError:(NSError *)error;
- (void)handlePendingRequests;
- (void)obtainRemoteConfig:(QONRemoteConfigCompletionHandler)completion;
- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion;
- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion;
- (void)userHasBeenChanged;

@end

NS_ASSUME_NONNULL_END
