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
  return [self makeRequestWithDictBody:parameters baseURL:self.baseURL endpoint:kSendPushTokenEndpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithDictBody:parameters baseURL:self.baseURL endpoint:kInitEndpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeUserInfoRequestWithID:(NSString *)userID apiKey:(NSString *)apiKey {
  NSString *endpoint = [NSString stringWithFormat:kUserInfoEndpoint, userID];
  return [self makeGetRequestWithBaseURL:self.baseURL endpoint:endpoint];
}

- (NSURLRequest *)makeSendPropertiesRequestForUserId:(NSString *)userId parameters:(NSArray *)parameters {
  NSString *endpoint = [NSString stringWithFormat:kPropertiesEndpoint, userId];

  return [self makeRequestWithArrayBody:parameters baseURL:self.baseURL endpoint:endpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeGetPropertiesRequestForUserId:(NSString *)userId {
  NSString *endpoint = [NSString stringWithFormat:kPropertiesEndpoint, userId];

  return [self makeGetRequestWithBaseURL:self.baseURL endpoint:endpoint];
}

- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithDictBody:parameters baseURL:self.baseURL endpoint:kAttributionEndpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithDictBody:parameters baseURL:self.baseURL endpoint:kPurchaseEndpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeUserActionPointsRequestWith:(NSString *)parameter {
  NSString *endpoint = [NSString stringWithFormat:kActionPointsEndpointFormat, parameter];
  return [self makeGetRequestWithBaseURL:self.baseURL endpoint:endpoint];
}

- (NSURLRequest *)makeScreensRequestWith:(NSString *)parameters {
  NSString *endpoint = [NSString stringWithFormat:@"%@%@", kScreensEndpoint, parameters];
  return [self makeGetRequestWithBaseURL:self.baseURL endpoint:endpoint];
}

- (NSURLRequest *)makeScreenShownRequestWith:(NSString *)parameter body:(NSDictionary *)body {
  NSString *endpoint = [NSString stringWithFormat:kScreenShowEndpointFormat, parameter];
  return [self makeRequestWithDictBody:body baseURL:self.baseURL endpoint:endpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeCreateIdentityRequestWith:(NSDictionary *)parameters {
  return [self makeRequestWithDictBody:parameters baseURL:self.baseURL endpoint:kIdentityEndpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeIntroTrialEligibilityRequestWithData:(NSDictionary *)parameters {
  return [self makeRequestWithDictBody:parameters baseURL:self.baseURL endpoint:kProductsEndpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeRemoteConfigRequestForUserId:(NSString *)userId contextKey:(NSString *)contextKey {
  NSMutableURLRequest *request = [[self makeGetRequestWithBaseURL:self.baseURL endpoint:kRemoteConfigEndpoint] mutableCopy];
  NSString *updatedURLString = [request.URL.absoluteString stringByAppendingString:[NSString stringWithFormat:@"?user_id=%@", userId]];
  if (contextKey) {
    updatedURLString = [updatedURLString stringByAppendingString:[NSString stringWithFormat:@"&context_key=%@", contextKey]];
  }
  [request setURL:[NSURL URLWithString:updatedURLString]];
  
  return [request copy];
}

- (NSURLRequest *)makeRemoteConfigListRequestForUserId:(NSString *)userId contextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey {
  NSMutableURLRequest *request = [[self makeGetRequestWithBaseURL:self.baseURL endpoint:kRemoteConfigListEndpoint] mutableCopy];
  NSString *updatedURLString = [request.URL.absoluteString stringByAppendingString:[NSString stringWithFormat:@"?user_id=%@&with_empty_context_key=%@", userId, includeEmptyContextKey ? @"true" : @"false"]];
  for (NSString *contextKey in contextKeys) {
    updatedURLString = [updatedURLString stringByAppendingString:[NSString stringWithFormat:@"&context_key=%@", contextKey]];
  }
  [request setURL:[NSURL URLWithString:updatedURLString]];
  
  return [request copy];
}

- (NSURLRequest *)makeRemoteConfigListRequestForUserId:(NSString *)userId {
  NSMutableURLRequest *request = [[self makeGetRequestWithBaseURL:self.baseURL endpoint:kRemoteConfigListEndpoint] mutableCopy];
  NSString *updatedURLString = [request.URL.absoluteString stringByAppendingString:[NSString stringWithFormat:@"?user_id=%@&all_context_keys=true", userId]];
  [request setURL:[NSURL URLWithString:updatedURLString]];
  
  return [request copy];
}

- (NSURLRequest *)makeAttachUserToExperimentRequest:(NSString *)experimentId groupId:(NSString *)groupId userID:(NSString *)userID {
  NSDictionary *params = @{@"group_id": groupId};
  NSString *endpoint = [NSString stringWithFormat:kAttachUserToExperimentEndpointFormat, experimentId, userID];
  return [self makeRequestWithDictBody:params baseURL:self.baseURL endpoint:endpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeDetachUserFromExperimentRequest:(NSString *)experimentId userID:(NSString *)userID {
  NSString *endpoint = [NSString stringWithFormat:kAttachUserToExperimentEndpointFormat, experimentId, userID];
  return [self makeRequestWithDictBody:nil baseURL:self.baseURL endpoint:endpoint type:QONRequestTypeDelete];
}

- (NSURLRequest *)makeAttachUserToRemoteConfigurationRequest:(NSString *)remoteConfigurationId userID:(NSString *)userID {
  NSString *endpoint = [NSString stringWithFormat:kAttachUserToRemoteConfigurationEndpointFormat, remoteConfigurationId, userID];
  return [self makeRequestWithDictBody:nil baseURL:self.baseURL endpoint:endpoint type:QONRequestTypePost];
}

- (NSURLRequest *)makeDetachUserFromRemoteConfigurationRequest:(NSString *)remoteConfigurationId userID:(NSString *)userID {
  NSString *endpoint = [NSString stringWithFormat:kAttachUserToRemoteConfigurationEndpointFormat, remoteConfigurationId, userID];
  return [self makeRequestWithDictBody:nil baseURL:self.baseURL endpoint:endpoint type:QONRequestTypeDelete];
}

- (NSURLRequest *)makeSdkLogsRequestWithBody:(NSDictionary *)body {
  return [self makeRequestWithDictBody:body baseURL:kSdkLogsBaseURL endpoint:kSdkLogsEndpoint type:QONRequestTypePost];
}

// MARK: Private

- (NSURLRequest *)makeGetRequestWithBaseURL:(NSString *)baseURL endpoint:(NSString *)endpoint {
  return [self makeRequestWithBaseURL:baseURL endpoint:endpoint data:nil type:QONRequestTypeGet];
}

- (NSURLRequest *)makeRequestWithDictBody:(NSDictionary *)body baseURL: (NSString *)baseURL endpoint:(NSString *)endpoint type:(QONRequestType)type {
  NSMutableDictionary *mutableBody = body.mutableCopy ?: [NSMutableDictionary new];
  NSData *data = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];

  return [self makeRequestWithBaseURL:baseURL endpoint:endpoint data:data type:type];
}

- (NSURLRequest *)makeRequestWithArrayBody:(NSArray *)body baseURL: (NSString *)baseURL endpoint:(NSString *)endpoint type:(QONRequestType)type {
  NSMutableArray *mutableBody = body.mutableCopy ?: [NSMutableArray new];
  NSData *data = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];

  return [self makeRequestWithBaseURL:baseURL endpoint:endpoint data:data type:type];
}

- (NSURLRequest *)makeRequestWithBaseURL:(NSString *)baseURL endpoint:(NSString *)endpoint data:(NSData *)data type:(QONRequestType)type {
  NSString *urlString = [baseURL stringByAppendingString:endpoint];
  NSURL *url = [NSURL URLWithString:urlString];
  
  switch (type) {
    case QONRequestTypeGet:
      return [self baseRequestWithURL:url type:@"GET"]; break;
    case QONRequestTypePost:
      return [self makeRequestWithURL:url data:data type:@"POST"]; break;
    case QONRequestTypeDelete:
      return [self makeRequestWithURL:url data:data type:@"DELETE"]; break;
  }
  
  return nil;
}

- (NSURLRequest *)makeRequestWithURL:(NSURL *)url data:(NSData *)data type:(NSString *)type {
  NSMutableURLRequest *request = [self baseRequestWithURL:url type:type];
  request.HTTPBody = data;
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
  NSString *version = [[NSUserDefaults standardUserDefaults] stringForKey:keyQSourceVersion] ?: self.version;
  NSString *sourceVersion = version ?: @"";
  
  [request addValue:platform forHTTPHeaderField:@"Platform"];
  [request addValue:platformVersion forHTTPHeaderField:@"Platform-Version"];
  [request addValue:source forHTTPHeaderField:@"Source"];
  [request addValue:sourceVersion forHTTPHeaderField:@"Source-Version"];
}

@end
