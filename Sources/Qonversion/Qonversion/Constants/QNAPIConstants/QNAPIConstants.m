//
//  QNAPIConstants.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 28.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNAPIConstants.h"

NSString * const kAPIBase = @"https://api.qonversion.io/";
NSString * const kSdkLogsBaseURL = @"https://sdk-logs.qonversion.io/";

NSString * const kInitEndpoint = @"v1/user/init";
NSString * const kSendPushTokenEndpoint = @"v1/user/push-token";
NSString * const kPurchaseEndpoint = @"v1/user/purchase";
NSString * const kProductsEndpoint = @"v1/products/get";
NSString * const kPropertiesEndpoint = @"v3/users/%@/properties";
NSString * const kRemoteConfigEndpoint = @"v3/remote-config";
NSString * const kRemoteConfigListEndpoint = @"v3/remote-configs";

NSString * const kAttachUserToExperimentEndpointFormat = @"v3/experiments/%@/users/%@";
NSString * const kAttachUserToRemoteConfigurationEndpointFormat = @"v3/remote-configurations/%@/users/%@";

NSString * const kActionPointsEndpointFormat = @"v2/users/%@/action-points?type=screen_view&active=1";
NSString * const kScreensEndpoint = @"v2/screens/";
NSString * const kScreenShowEndpointFormat = @"v2/screens/%@/views";
NSString * const kIdentityEndpoint = @"v2/identities";
NSString * const kUserInfoEndpoint = @"v2/users/%@";

NSString * const kEventEndpoint = @"v2/events";

NSString * const kAttributionEndpoint = @"attribution";

NSString * const kSdkLogsEndpoint = @"sdk.log";

NSString * const kStoredRequestsKey = @"storedRequests";

NSString * const kAccessDeniedError = @"Access denied";
NSString * const kInternalServerError = @"Internal server error";

NSUInteger const kMaxSimilarRequestsPerSecond = 5;
