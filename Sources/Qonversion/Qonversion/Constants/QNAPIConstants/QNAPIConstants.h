//
//  QNAPIConstants.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 28.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const kAPIBase;
extern NSString *const kInitEndpoint;
extern NSString *const kPurchaseEndpoint;
extern NSString *const kPostPromoOfferDetailsEndpoint;
extern NSString *const kProductsEndpoint;
extern NSString *const kPropertiesEndpoint;
extern NSString *const kActionPointsEndpointFormat;
extern NSString *const kScreensEndpoint;
extern NSString *const kScreenShowEndpointFormat;
extern NSString *const kIdentityEndpoint;
extern NSString *const kUserInfoEndpoint;
extern NSString *const kAttributionEndpoint;
extern NSString *const kAttachUserToExperimentEndpointFormat;
extern NSString *const kAttachUserToRemoteConfigurationEndpointFormat;
extern NSString *const kSdkLogsEndpoint;
extern NSString *const kSdkLogsBaseURL;
extern NSString *const kStoredRequestsKey;
extern NSString *const kRemoteConfigEndpoint;
extern NSString *const kRemoteConfigListEndpoint;

/// Pinned host for inbound Web 2 App redemption Universal Links
/// (`https://screens.qonversion.io/r/{project_uid}/{token}`). Used to reject
/// look-alike / foreign hosts before issuing a redeem request.
extern NSString *const kRedemptionLinkHost;

extern NSString *const kWebRedeemEndpoint;
extern NSString *const kWebRedeemStatusEndpoint;
extern NSString *const kWebRedeemReissueEndpoint;

extern NSString *const kEventEndpoint;

extern NSString *const kAccessDeniedError;
extern NSString *const kInternalServerError;

extern NSUInteger const kMaxSimilarRequestsPerSecond;
