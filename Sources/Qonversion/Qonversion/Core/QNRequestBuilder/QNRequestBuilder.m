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
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kSendPushTokenEndpoint body:parameters type:QONRequestTypePost];
}

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kInitEndpoint body:parameters type:QONRequestTypePost];
}

- (NSURLRequest *)makeUserInfoRequestWithID:(NSString *)userID apiKey:(NSString *)apiKey {
  NSString *endpoint = [NSString stringWithFormat:kUserInfoEndpoint, userID];
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kUserInfoEndpoint body:nil type:QONRequestTypeGet];
}

- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kPropertiesEndpoint body:parameters type:QONRequestTypePost];
}

- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kAttributionEndpoint body:parameters type:QONRequestTypePost];
}

- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kPurchaseEndpoint body:parameters type:QONRequestTypePost];
}

- (NSURLRequest *)makeUserActionPointsRequestWith:(NSString *)parameter {
  NSString *endpoint = [NSString stringWithFormat:kActionPointsEndpointFormat, parameter];
  return [self makeRequestWithBaseURL:self.baseURL endpoint:endpoint body:nil type:QONRequestTypeGet];
}

- (NSURLRequest *)makeScreensRequestWith:(NSString *)parameters {
  NSString *endpoint = [NSString stringWithFormat:@"%@%@", kScreensEndpoint, parameters];
  return [self makeRequestWithBaseURL:self.baseURL endpoint:endpoint body:nil type:QONRequestTypeGet];
}

- (NSURLRequest *)makeScreenShownRequestWith:(NSString *)parameter body:(NSDictionary *)body {
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kScreenShowEndpointFormat body:body type:QONRequestTypePost];
}

- (NSURLRequest *)makeCreateIdentityRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kIdentityEndpoint body:parameters type:QONRequestTypePost];
}

- (NSURLRequest *)makeIntroTrialEligibilityRequestWithData:(NSDictionary *)parameters {
  return [self makeRequestWithBaseURL:self.baseURL endpoint:kProductsEndpoint body:parameters type:QONRequestTypePost];
}

- (NSURLRequest *)remoteConfigRequestForUserId:(NSString *)userId {
  NSURLRequest *request = [self makeRequestWithBaseURL:self.baseURL endpoint:kRemoteConfigEndpoint body:nil type:QONRequestTypeGet];
  
  NSMutableURLRequest *mutableRequest = [request mutableCopy];
  NSString *updatedURLString = [mutableRequest.URL.absoluteString stringByAppendingString:[NSString stringWithFormat:@"?user_id=%@", userId]];
  [mutableRequest setURL:[NSURL URLWithString:updatedURLString]];
  
  return [mutableRequest copy];
}

- (NSURLRequest *)makeAttachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId userID:(NSString *)userID {
  NSDictionary *params = @{@"group_id": groupId};
  NSString *endpoint = [NSString stringWithFormat:kAttachUserToExperimentEndpointFormat, experimentId, userID];
  return [self makeRequestWithBaseURL:self.baseURL endpoint:endpoint body:params type:QONRequestTypePost];
}

- (NSURLRequest *)makeDetachUserToExperiment:(NSString *)experimentId userID:(NSString *)userID {
  NSString *endpoint = [NSString stringWithFormat:kAttachUserToExperimentEndpointFormat, experimentId, userID];
  return [self makeRequestWithBaseURL:self.baseURL endpoint:endpoint body:nil type:QONRequestTypeDelete];
}

- (NSURLRequest *)makeSdkLogsRequestWithBody:(NSDictionary *)body {
  return [self makeRequestWithBaseURL:kSdkLogsBaseURL endpoint:kSdkLogsEndpoint body:body type:QONRequestTypePost];
}

// MARK: Private

- (NSURLRequest *)makeRequestWithBaseURL:(NSString *)baseURL endpoint:(NSString *)endpoint body:(NSDictionary *)body type:(QONRequestType)type {
  NSString *urlString = [baseURL stringByAppendingString:endpoint];
  NSURL *url = [NSURL URLWithString:urlString];
  
  switch (type) {
    case QONRequestTypeGet:
      return [self baseRequestWithURL:url type:@"GET"]; break;
    case QONRequestTypePost:
      return [self makeRequestWithURL:url body:body type:@"POST"]; break;
    case QONRequestTypeDelete:
      return [self makeRequestWithURL:url body:body type:@"DELETE"]; break;
  }
  
  return nil;
}

- (NSURLRequest *)makeRequestWithURL:(NSURL *)url body:(NSDictionary *)body type:(NSString *)type {
  NSMutableURLRequest *request = [self baseRequestWithURL:url type:type];
  
  NSMutableDictionary *mutableBody = body.mutableCopy ?: [NSMutableDictionary new];
  
  request.HTTPBody = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];
  return [request copy];
}

- (NSMutableURLRequest *)baseRequestWithURL:(NSURL *)url type:(NSString *)type {
  NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL: url];
  
  request.HTTPMethod = type;
  [request addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
  [self addBearerToRequest:request];
  [self addLocaleToRequest:request];
  [self addPlatformInfoToRequest:request];
  [self addAppVersionToRequest:request];
  [self addCountryToRequest:request];
  
  return request;
}

- (void)addAppVersionToRequest:(NSMutableURLRequest *)request {
  [request addValue:[[QNDevice current] appVersion] forHTTPHeaderField:@"app-version"];
}

- (void)addCountryToRequest:(NSMutableURLRequest *)request {
  [request addValue:[[QNDevice current] country] forHTTPHeaderField:@"country"];
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
