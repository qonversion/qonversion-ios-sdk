#import "QNRequestBuilder.h"
#import "QNAPIConstants.h"
#import "QNDevice.h"
#import "QNInternalConstants.h"

@interface QNRequestBuilder ()

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *baseURL;

@end

@implementation QNRequestBuilder

- (void)setApiKey:(NSString *)apiKey {
  _apiKey = apiKey;
}

- (void)setSDKVersion:(NSString *)version {
  _version = version;
}

- (void)setBaseURL:(NSString *)url {
  _baseURL = url;
}

- (NSURLRequest *)makeSendPushTokenRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWithEndpoint:kSendPushTokenEndpoint body:parameters];
}

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWithEndpoint:kInitEndpoint body:parameters];
}

- (NSURLRequest *)makeUserInfoRequestWithID:(NSString *)userID apiKey:(NSString *)apiKey {
  NSString *endpoint = [NSString stringWithFormat:kUserInfoEndpoint, userID];
  return [self makeGetRequestWith:endpoint];
}

- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWithEndpoint:kPropertiesEndpoint body:parameters];
}

- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWithEndpoint:kAttributionEndpoint body:parameters];
}

- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWithEndpoint:kPurchaseEndpoint body:parameters];
}

- (NSURLRequest *)makeUserActionPointsRequestWith:(NSString *)parameter {
  NSString *endpoint = [NSString stringWithFormat:kActionPointsEndpointFormat, parameter];
  return [self makeGetRequestWith:endpoint];
}

- (NSURLRequest *)makeScreensRequestWith:(NSString *)parameters {
  NSString *endpoint = [NSString stringWithFormat:@"%@%@", kScreensEndpoint, parameters];
  return [self makeGetRequestWith:endpoint];
}

- (NSURLRequest *)makeScreenShownRequestWith:(NSString *)parameter body:(NSDictionary *)body {
  NSString *endpoint = [NSString stringWithFormat:kScreenShowEndpointFormat, parameter];
  return [self makePostRequestWithEndpoint:endpoint body:body];
}

- (NSURLRequest *)makeCreateIdentityRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWithEndpoint:kIdentityEndpoint body:parameters];
}

- (NSURLRequest *)makeIntroTrialEligibilityRequestWithData:(NSDictionary *)parameters {
  return [self makePostRequestWithEndpoint:kProductsEndpoint body:parameters];
}

- (NSURLRequest *)makeEventRequestWithEventName:(NSString *)eventName payload:(NSDictionary *)payload userID:(NSString *)userID {
  NSMutableDictionary *body = [NSMutableDictionary new];
  body[@"user"] = userID;
  body[@"event"] = eventName;
  body[@"payload"] = payload;
  
  return [self makePostRequestWithEndpoint:kEventEndpoint body:[body copy]];
}

- (NSURLRequest *)makeSdkLogsRequestWithBody:(NSDictionary *)body {
  return [self makePostRequestWithEndpoint:kSdkLogsEndpoint body:body baseUrl:kSdkLogsBaseURL];
}

// MARK: Private

- (NSURLRequest *)makeGetRequestWith:(NSString *)endpoint {
  NSString *urlString = [self.baseURL stringByAppendingString:endpoint];
  NSURL *url = [[NSURL alloc] initWithString:urlString];

  NSMutableURLRequest *request = [self baseGetRequestWithURL:url];
  
  return [request copy];
}

- (NSURLRequest *)makePostRequestWithEndpoint:(NSString *)endpoint body:(NSDictionary *)body {
  return [self makePostRequestWithEndpoint:endpoint body:body baseUrl:self.baseURL];
}

- (NSURLRequest *)makePostRequestWithEndpoint:(NSString *)endpoint body:(NSDictionary *)body baseUrl:(NSString *)baseURL {
  NSString *urlString = [baseURL stringByAppendingString:endpoint];
  NSURL *url = [NSURL URLWithString:urlString];

  NSMutableURLRequest *request = [self basePostRequestWithURL:url];
  
  NSMutableDictionary *mutableBody = body.mutableCopy ?: [NSMutableDictionary new];

  request.HTTPBody = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];
  
  return [request copy];
}

- (NSMutableURLRequest *)basePostRequestWithURL:(NSURL *)url {
  return [self baseRequestWithURL:url type:@"POST"];
}

- (NSMutableURLRequest *)baseGetRequestWithURL:(NSURL *)url {
  return [self baseRequestWithURL:url type:@"GET"];
}

- (NSMutableURLRequest *)baseRequestWithURL:(NSURL *)url type:(NSString *)type {
  NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL: url];
  
  request.HTTPMethod = type;
  [request addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
  [self addBearerToRequest:request];
  [self addLocaleToRequest:request];
  [self addPlatformInfoToRequest:request];

  return request;
}

- (void)addLocaleToRequest:(NSMutableURLRequest *)request {
  NSString *currentLocaleIdentifier = [NSLocale currentLocale].localeIdentifier;
  NSString *locale = [NSLocale componentsFromLocaleIdentifier:currentLocaleIdentifier][NSLocaleLanguageCode];
  if (locale.length > 0) {
    [request addValue:locale forHTTPHeaderField:@"User-locale"];
  }
}

- (void)addBearerToRequest:(NSMutableURLRequest *)request {
  if (self.apiKey.length > 0) {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
    [request addValue:authHeader forHTTPHeaderField:@"Authorization"];
  }
}

- (void)addPlatformInfoToRequest:(NSMutableURLRequest *)request {
  NSString *platformVersion = [QNDevice current].osVersion;
  NSString *platform = [QNDevice current].osName;
  NSString *source = [[NSUserDefaults standardUserDefaults] stringForKey:keyQSource] ?: @"iOS";
  NSString *sourceVersion = [[NSUserDefaults standardUserDefaults] stringForKey:keyQSourceVersion] ?: self.version;
  
  [request addValue:platform forHTTPHeaderField:@"Platform"];
  [request addValue:platformVersion forHTTPHeaderField:@"Platform-Version"];
  [request addValue:source forHTTPHeaderField:@"Source"];
  [request addValue:sourceVersion forHTTPHeaderField:@"Source-Version"];
}

@end
