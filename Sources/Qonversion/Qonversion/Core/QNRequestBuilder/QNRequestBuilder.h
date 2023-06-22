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
- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeUserActionPointsRequestWith:(NSString *)parameter;
- (NSURLRequest *)makeScreensRequestWith:(NSString *)parameters;
- (NSURLRequest *)makeCreateIdentityRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeScreenShownRequestWith:(NSString *)parameter body:(NSDictionary *)body;
- (NSURLRequest *)makeIntroTrialEligibilityRequestWithData:(NSDictionary *)parameters;
- (NSURLRequest *)remoteConfigRequestForUserId:(NSString *)userId;
- (NSURLRequest *)makeSdkLogsRequestWithBody:(NSDictionary *)body;
- (NSURLRequest *)makeAttachUserToExperimentRequest:(NSString *)experimentId groupId:(NSString *)groupId userID:(NSString *)userID;
- (NSURLRequest *)makeDetachUserToExperimentRequest:(NSString *)experimentId userID:(NSString *)userID;

@end
