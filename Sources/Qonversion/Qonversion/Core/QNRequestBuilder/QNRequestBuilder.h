#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, QONRequestType) {
  QONRequestTypeGet = 0,
  QONRequestTypePost,
  QONRequestTypeDelete
};

@interface QNRequestBuilder : NSObject

- (void)setApiKey:(NSString *)apiKey;
- (void)setBaseURL:(NSString *)url;
- (void)setSDKVersion:(NSString *)version;
- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeSendPushTokenRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeUserInfoRequestWithID:(NSString *)userID apiKey:(NSString *)apiKey;
- (NSURLRequest *)makeSendPropertiesRequestForUserId:(NSString *)userId parameters:(NSArray *)parameters;
- (NSURLRequest *)makeGetPropertiesRequestForUserId:(NSString *)userId;
- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeUserActionPointsRequestWith:(NSString *)parameter;
- (NSURLRequest *)makeScreensRequestWith:(NSString *)parameters;
- (NSURLRequest *)makeCreateIdentityRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeScreenShownRequestWith:(NSString *)parameter body:(NSDictionary *)body;
- (NSURLRequest *)makeIntroTrialEligibilityRequestWithData:(NSDictionary *)parameters;
- (NSURLRequest *)makeRemoteConfigRequestForUserId:(NSString *)userId contextKey:(NSString *)contextKey;
- (NSURLRequest *)makeRemoteConfigListRequestForUserId:(NSString *)userId contextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey;
- (NSURLRequest *)makeRemoteConfigListRequestForUserId:(NSString *)userId;
- (NSURLRequest *)makeSdkLogsRequestWithBody:(NSDictionary *)body;
- (NSURLRequest *)makeAttachUserToExperimentRequest:(NSString *)experimentId groupId:(NSString *)groupId userID:(NSString *)userID;
- (NSURLRequest *)makeDetachUserFromExperimentRequest:(NSString *)experimentId userID:(NSString *)userID;
- (NSURLRequest *)makeAttachUserToRemoteConfigurationRequest:(NSString *)remoteConfigurationId userID:(NSString *)userID;
- (NSURLRequest *)makeDetachUserFromRemoteConfigurationRequest:(NSString *)remoteConfigurationId userID:(NSString *)userID;

@end
