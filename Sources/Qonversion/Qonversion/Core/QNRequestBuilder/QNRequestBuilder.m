#import "QNRequestBuilder.h"
#import "QNAPIConstants.h"
#import "QNDevice.h"
#import "QNConstants.h"

@interface QNRequestBuilder ()

@property (nonatomic, copy) NSString *apiKey;

@end

@implementation QNRequestBuilder

- (void)setApiKey:(NSString *)apiKey {
  _apiKey = apiKey;
}

- (NSURLRequest *)makeSendPushTokenRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWith:kSendPushTokenEndpoint andBody:parameters];
}

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWith:kInitEndpoint andBody:parameters];
}

- (NSURLRequest *)makeUserInfoRequestWithID:(NSString *)userID apiKey:(NSString *)apiKey {
  NSString *endpoint = [NSString stringWithFormat:kUserInfoEndpoint, userID];
  return [self makeGetRequestWith:endpoint];
}

- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWith:kPropertiesEndpoint andBody:parameters];
}

- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWith:kAttributionEndpoint andBody:parameters];
}

- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWith:kPurchaseEndpoint andBody:parameters];
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
  return [self makePostRequestWith:endpoint andBody:body];
}

- (NSURLRequest *)makeCreateIdentityRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWith:kIdentityEndpoint andBody:parameters];
}

- (NSURLRequest *)makeIntroTrialEligibilityRequestWithData:(NSDictionary *)parameters {
  return [self makePostRequestWith:kProductsEndpoint andBody:parameters];
}

- (NSURLRequest *)makeEventRequestWithEventName:(NSString *)eventName payload:(NSDictionary *)payload userID:(NSString *)userID {
  NSMutableDictionary *body = [NSMutableDictionary new];
  body[@"user"] = userID;
  body[@"event"] = eventName;
  body[@"payload"] = payload;
  
  return [self makePostRequestWith:kEventEndpoint andBody:[body copy]];
}

// MARK: Private

- (NSURLRequest *)makeGetRequestWith:(NSString *)endpoint {
  NSString *urlString = [kAPIBase stringByAppendingString:endpoint];
  NSURL *url = [[NSURL alloc] initWithString:urlString];

  NSMutableURLRequest *request = [self baseGetRequestWithURL:url];
  
  return [request copy];
}

- (NSURLRequest *)makePostRequestWith:(NSString *)endpoint andBody:(NSDictionary *)body {
  NSString *urlString = [kAPIBase stringByAppendingString:endpoint];
  NSURL *url = [NSURL.alloc initWithString:urlString];

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
  NSString *sourceVersion = [[NSUserDefaults standardUserDefaults] stringForKey:keyQSourceVersion] ?: keyQVersion;
  
  [request addValue:platform forHTTPHeaderField:@"Platform"];
  [request addValue:platformVersion forHTTPHeaderField:@"Platform-Version"];
  [request addValue:source forHTTPHeaderField:@"Source"];
  [request addValue:sourceVersion forHTTPHeaderField:@"Source-Version"];
}

@end
