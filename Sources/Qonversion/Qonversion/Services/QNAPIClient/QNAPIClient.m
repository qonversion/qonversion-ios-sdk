#import "QNAPIClient.h"
#import "QNInternalConstants.h"
#import "QNRequestBuilder.h"
#import "QNRequestSerializer.h"
#import "QONErrors.h"
#import "QNUtils.h"
#import "QNAPIConstants.h"
#import "QNErrorsMapper.h"
#import "QNKeyedArchiver.h"
#import "QONStoreKit2PurchaseModel.h"
#import "QNDevice.h"
#import "QONRateLimiter.h"
#import "QNLocalStorage.h"
#import "Qonversion.h"

NSUInteger const kUnableToParseEmptyDataDefaultCode = 3840;

@interface QNAPIClient()

@property (nonatomic, strong) QNRequestSerializer *requestSerializer;
@property (nonatomic, strong) QNRequestBuilder *requestBuilder;
@property (nonatomic, strong) QNErrorsMapper *errorsMapper;
@property (nonatomic, strong) QONRateLimiter *rateLimiter;
@property (nonatomic, copy) NSArray<NSString *> *retriableRequests;
@property (nonatomic, copy) NSArray<NSNumber *> *criticalErrorCodes;
@property (nonatomic, strong) NSError *criticalError;
@property (nonatomic, copy) NSString *version;

@end

@implementation QNAPIClient

- (instancetype)init {
  self = super.init;
  if (self) {
    _requestSerializer = [[QNRequestSerializer alloc] init];
    _requestBuilder = [[QNRequestBuilder alloc] init];
    _errorsMapper = [QNErrorsMapper new];
    _rateLimiter = [[QONRateLimiter alloc] initWithMaxRequestsPerSecond:kMaxSimilarRequestsPerSecond];
    
    _apiKey = @"";
    _userID = @"";
    _debug = NO;
    _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    _retriableRequests = @[kInitEndpoint, kPurchaseEndpoint, kAttributionEndpoint];
    _criticalErrorCodes = [QNUtils authErrorsCodes];
  }
  
  return self;
}

+ (instancetype)shared {
  static id shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = self.new;
  });
  
  return shared;
}

- (void)setApiKey:(NSString *)apiKey {
  _apiKey = apiKey;
  [self.requestBuilder setApiKey:[self obtainApiKey]];
}

- (void)setSDKVersion:(NSString *)version {
  _version = version;
  [self.requestBuilder setSDKVersion:version];
}

- (void)setBaseURL:(NSString *)url {
  [self.requestBuilder setBaseURL:url];
}

- (void)setDebug:(BOOL)debug {
  _debug = debug;
  [self.requestBuilder setApiKey:[self obtainApiKey]];
}

- (void)processRequestWithoutResponse:(NSURLRequest *)request completion:(QNAPIClientEmptyCompletionHandler)completion {
  [self processRequest:request parseResponse:NO completion:^(id _Nullable data, NSError * _Nullable error) {
      completion(error);
  }];
}

- (void)processDictRequest:(NSURLRequest *)request completion:(QNAPIClientDictCompletionHandler)completion {
  [self processRequest:request parseResponse:YES completion:^(id _Nullable data, NSError * _Nullable error) {
      if (error != nil || [data isKindOfClass:[NSDictionary class]]) {
        completion(data, error);
      } else {
        completion(nil, [QONErrors errorWithCode:QONAPIErrorFailedParseResponse]);
      }
  }];
}

- (void)processArrayRequest:(NSURLRequest *)request completion:(QNAPIClientArrayCompletionHandler)completion {
  [self processRequest:request parseResponse:YES completion:^(id _Nullable data, NSError * _Nullable error) {
      if (error != nil || [data isKindOfClass:[NSArray class]]) {
        completion(data, error);
      } else {
        completion(nil, [QONErrors errorWithCode:QONAPIErrorFailedParseResponse]);
      }
  }];
}

- (void)processRequest:(NSURLRequest *)request parseResponse:(BOOL)parseResponse completion:(QNAPIClientCommonCompletionHandler)completion {
  [self dataTaskWithRequest:request parseResponse:parseResponse completion:^(id _Nullable data, NSError * _Nullable error) {
    if (!self.criticalError && error && [self.criticalErrorCodes containsObject:@(error.code)]) {
      self.criticalError = error;
    }

    if (completion) {
      completion(data, error);
    }
  }];
}

// MARK: - Public

- (void)sendPushToken:(void (^)(BOOL success))completion {
  NSDictionary *data = [self.requestSerializer pushTokenData];
  data = [self enrichPushTokenData:data];
  NSURLRequest *request = [self.requestBuilder makeSendPushTokenRequestWith:data];
  
  [self processDictRequest:request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    BOOL isSuccess = error == nil;
    completion(isSuccess);
  }];
}

- (void)launchRequest:(QNAPIClientDictCompletionHandler)completion {
  NSDictionary *launchData = [self.requestSerializer launchData];

  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeInit
                               params:launchData
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSDictionary *enrichedData = [self enrichParameters:launchData];
    NSURLRequest *request = [self.requestBuilder makeInitRequestWith:enrichedData];
    [self processDictRequest:request completion:completion];
  }];
}

- (NSURLRequest *)handlePurchase:(QONStoreKit2PurchaseModel *)purchaseInfo
               receipt:(nullable NSString *)receipt
            completion:(QNAPIClientDictCompletionHandler)completion {
  NSDictionary *body = [self.requestSerializer purchaseInfo:purchaseInfo receipt:receipt];
  NSDictionary *resultData = [self enrichParameters:body];
  
  NSURLRequest *request = [self.requestBuilder makePurchaseRequestWith:resultData];

  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypePurchase
                               params:body
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    [self processDictRequest:request completion:completion];
  }];
  
  return [request copy];
}

- (NSURLRequest *)purchaseRequestWith:(SKProduct *)product
                          transaction:(SKPaymentTransaction *)transaction
                              receipt:(nullable NSString *)receipt
                           completion:(QNAPIClientDictCompletionHandler)completion {
  NSDictionary *body = [self.requestSerializer purchaseData:product transaction:transaction receipt:receipt];
  return [self purchaseRequestWith:body completion:completion];
}

- (NSURLRequest *)purchaseRequestWith:(NSDictionary *)body
                           completion:(QNAPIClientDictCompletionHandler)completion {
  NSDictionary *resultData = [self enrichParameters:body];

  NSURLRequest *request = [self.requestBuilder makePurchaseRequestWith:resultData];

  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypePurchase
                               params:body
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    [self processDictRequest:request completion:completion];
  }];

  return [request copy];
}

- (void)checkTrialIntroEligibilityParamsForProducts:(NSArray<QONProduct *> *)products
                                         completion:(QNAPIClientDictCompletionHandler)completion {
  NSDictionary *requestData = [self.requestSerializer introTrialEligibilityDataForProducts:products];
  
  return [self checkTrialIntroEligibilityParamsForData:requestData completion:completion];
}

- (void)checkTrialIntroEligibilityParamsForData:(NSDictionary *)data
                                     completion:(QNAPIClientDictCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeEligibilityForProducts
                               params:data
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSDictionary *resultBody = [self enrichParameters:data];
    NSURLRequest *request = [self.requestBuilder makeIntroTrialEligibilityRequestWithData:resultBody];

    return [self processDictRequest:request completion:completion];
  }];
}

- (void)sendProperties:(NSDictionary *)properties completion:(QNAPIClientDictCompletionHandler)completion {
  NSMutableArray *propertiesForApi = [NSMutableArray new];
  NSArray *keys = [properties allKeys];
  for (NSString *key in keys) {
    NSString *value = properties[key];
    NSDictionary *keyValueObject = @{@"key": key, @"value": value};
    [propertiesForApi addObject:keyValueObject];
  }

  NSURLRequest *request = [self.requestBuilder makeSendPropertiesRequestForUserId:_userID parameters:propertiesForApi];

  [self processDictRequest:request completion:completion];
}

- (void)getProperties:(QNAPIClientArrayCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeGetProperties
                                 hash:[self.userID hash]
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeGetPropertiesRequestForUserId:self.userID];

    [self processArrayRequest:request completion:completion];
  }];
}

- (void)userActionPointsWithCompletion:(QNAPIClientDictCompletionHandler)completion {
  NSURLRequest *request = [self.requestBuilder makeUserActionPointsRequestWith:self.userID];
  
  return [self processDictRequest:request completion:completion];
}

- (void)automationWithID:(NSString *)automationID completion:(QNAPIClientDictCompletionHandler)completion {
  NSURLRequest *request = [self.requestBuilder makeScreensRequestWith:automationID];
  
  return [self processDictRequest:request completion:completion];
}

- (void)userInfoRequestWithID:(NSString *)userID completion:(QNAPIClientDictCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeUserInfo
                                 hash:[userID hash]
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeUserInfoRequestWithID:userID apiKey:[self obtainApiKey]];
    return [self processDictRequest:request completion:completion];
  }];
}

- (void)createIdentityForUserID:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNAPIClientDictCompletionHandler)completion {
  NSDictionary *parameters = @{@"anon_id": anonUserID, @"identity_id": userID};

  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeIdentify
                               params:parameters
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeCreateIdentityRequestWith:parameters];

    return [self processDictRequest:request completion:completion];
  }];
}

- (void)trackScreenShownWithID:(NSString *)automationID {
  return [self trackScreenShownWithID:automationID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {}];
}

- (void)trackScreenShownWithID:(NSString *)automationID
                    completion:(QNAPIClientDictCompletionHandler)completion {
  NSDictionary *body = @{@"user": self.userID};
  NSURLRequest *request = [self.requestBuilder makeScreenShownRequestWith:automationID body:body];
  
  return [self processDictRequest:request completion:completion];
}

- (void)attributionRequest:(QONAttributionProvider)provider
                      data:(NSDictionary *)data
                completion:(QNAPIClientDictCompletionHandler)completion {
  NSDictionary *body = [self.requestSerializer attributionDataWithDict:data fromProvider:provider];

  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeAttribution
                               params:body
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSDictionary *resultData = [self enrichParameters:body];
    NSURLRequest *request = [[self requestBuilder] makeAttributionRequestWith:resultData];
    [self processDictRequest:request completion:completion];
  }];
}

- (void)processStoredRequests {
  NSData *storedRequestsData = [self.localStorage loadObjectForKey:kStoredRequestsKey];
  NSArray *storedRequests = [QNKeyedArchiver unarchiveObjectWithData:storedRequestsData];
  
  if (![storedRequests isKindOfClass:[NSArray class]]) {
    [self.localStorage storeObject:nil forKey:kStoredRequestsKey];
  } else {
    for (NSInteger i = 0; i < [storedRequests count]; i++) {
      if ([storedRequests[i] isKindOfClass:[NSURLRequest class]]) {
        NSURLRequest *request = storedRequests[i];
        
        [self dataTaskWithRequest:request completion:nil];
      }
    }
    
    [self.localStorage storeObject:nil forKey:kStoredRequestsKey];
  }
  
  [self processStorePurchasesRequests];
}

- (void)processStorePurchasesRequests {
  NSDictionary *unarchivedData = [self storedPurchasesRequests];
  
  for (NSString *transactionId in unarchivedData.allKeys) {
    NSURLRequest *request = unarchivedData[transactionId];
    if ([request isKindOfClass:[NSURLRequest class]]) {
      [self dataTaskWithRequest:request completion:^(id _Nullable dict, NSError * _Nullable error) {
        if (![QNUtils shouldPurchaseRequestBeRetried:error]) {
          [self removeStoredRequestForTransactionId:transactionId];
        }
      }];
    }
  }
}

- (void)sendCrashReport:(NSDictionary *)data completion:(QNAPIClientEmptyCompletionHandler)completion {
  NSDictionary *body = [self enrichSdkLogParameters:data];
  NSURLRequest *request = [self.requestBuilder makeSdkLogsRequestWithBody:body];
  NSMutableURLRequest *mutableRequest = [request mutableCopy];
  [mutableRequest setAllHTTPHeaderFields:@{
          @"Content-Type": @"application/json"
  }];

  [self processRequestWithoutResponse:mutableRequest completion:completion];
}

- (void)loadRemoteConfig:(NSString * _Nullable)contextKey completion:(QNAPIClientDictCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeRemoteConfig
                                 hash:[self.userID hash]
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeRemoteConfigRequestForUserId:self.userID contextKey:contextKey];

    return [self processDictRequest:request completion:completion];
  }];
}

- (void)loadRemoteConfigList:(QNAPIClientArrayCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeRemoteConfigList
                                 hash:[self.userID hash]
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeRemoteConfigListRequestForUserId:self.userID];

    return [self processArrayRequest:request completion:completion];
  }];
}

- (void)loadRemoteConfigListForContextKeys:(NSArray<NSString *> *)contextKeys
                    includeEmptyContextKey:(BOOL)includeEmptyContextKey
                                completion:(QNAPIClientArrayCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeRemoteConfigList
                               params:@{@"contextKeys": contextKeys, @"userId": self.userID}
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(nil, rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeRemoteConfigListRequestForUserId:self.userID contextKeys:contextKeys includeEmptyContextKey:includeEmptyContextKey];

    return [self processArrayRequest:request completion:completion];
  }];
}

- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QNAPIClientEmptyCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeAttachUserToExperiment
                                 hash:[[NSString stringWithFormat:@"%@%@%@", self.userID, experimentId, groupId] hash]
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeAttachUserToExperimentRequest:experimentId groupId:groupId userID:self.userID];

    [self processRequestWithoutResponse:request completion:completion];
  }];
}

- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QNAPIClientEmptyCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeDetachUserFromExperiment
                                 hash:[[NSString stringWithFormat:@"%@%@", self.userID, experimentId] hash]
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeDetachUserFromExperimentRequest:experimentId userID:self.userID];

    [self processRequestWithoutResponse:request completion:completion];
  }];
}

- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QNAPIClientEmptyCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeAttachUserToRemoteConfiguration
                                 hash:[[NSString stringWithFormat:@"%@%@", self.userID, remoteConfigurationId] hash]
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeAttachUserToRemoteConfigurationRequest:remoteConfigurationId userID:self.userID];

    [self processRequestWithoutResponse:request completion:completion];
  }];
}

- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QNAPIClientEmptyCompletionHandler)completion {
  [self.rateLimiter validateRateLimit:QONRateLimitedRequestTypeDetachUserFromRemoteConfiguration
                                 hash:[[NSString stringWithFormat:@"%@%@", self.userID, remoteConfigurationId] hash]
                           completion:^(NSError *rateLimitError) {
    if (rateLimitError != nil) {
      completion(rateLimitError);
      return;
    }

    NSURLRequest *request = [self.requestBuilder makeDetachUserFromRemoteConfigurationRequest:remoteConfigurationId userID:self.userID];

    [self processRequestWithoutResponse:request completion:completion];
  }];
}

// MARK: - Private

- (NSDictionary *)enrichPushTokenData:(NSDictionary *)data {
  NSMutableDictionary *mutableData = [data mutableCopy];
  mutableData[@"access_token"] = _apiKey;
  mutableData[@"q_uid"] = _userID;
  
  return [mutableData copy];
}

- (NSString *)obtainApiKey {
  return self.debug ? [NSString stringWithFormat:@"test_%@", self.apiKey] : self.apiKey;
}

- (NSDictionary *)enrichParameters:(NSDictionary *)parameters {
  NSDictionary *_parameters = parameters ?: @{};

  NSMutableDictionary *baseDict = [[NSMutableDictionary alloc] initWithDictionary:_parameters];
  baseDict[@"access_token"] = _apiKey;

  baseDict[@"q_uid"] = _userID;
  baseDict[@"client_uid"] = _userID;
  baseDict[@"version"] = self.version;
  baseDict[@"debug_mode"] = @(self.debug);

  return [baseDict copy];
}

- (NSDictionary *)enrichSdkLogParameters:(NSDictionary *)parameters {
  NSMutableDictionary *mutableParameters = [parameters mutableCopy] ?: [NSMutableDictionary new];

  NSString *platformVersion = [QNDevice current].osVersion;
  NSString *platform = [QNDevice current].osName;
  NSString *source = [[NSUserDefaults standardUserDefaults] stringForKey:keyQSource] ?: @"iOS";
  NSString *sourceVersion = [[NSUserDefaults standardUserDefaults] stringForKey:keyQSourceVersion] ?: self.version;
  
  NSMutableDictionary *device = [NSMutableDictionary new];
  
  device[@"platform"] = platform;
  device[@"platform_version"] = platformVersion;
  device[@"source"] = source;
  device[@"source_version"] = sourceVersion;
  device[@"project_key"] = [self obtainApiKey];
  device[@"uid"] = self.userID;

  mutableParameters[@"device"] = device;

  return [mutableParameters copy];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request
                 completion:(QNAPIClientCommonCompletionHandler)completion {
  [self dataTaskWithRequest:request parseResponse:YES completion:completion];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request
              parseResponse:(BOOL)parseResponse
                 completion:(QNAPIClientCommonCompletionHandler)completion {
  if (self.criticalError) {
    if (completion) {
      completion(nil, self.criticalError);
    }
    return;
  }
  
  [self dataTaskWithRequest:request tryCount:0 parseResponse:parseResponse completion:completion];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request
                   tryCount:(NSInteger)tryCount
              parseResponse:(BOOL)parseResponse
                 completion:(QNAPIClientCommonCompletionHandler)completion {
  __block NSInteger doneTryCount = tryCount;
  
  __block __weak QNAPIClient *weakSelf = self;
  [[self.session dataTaskWithRequest:request completionHandler:^(id _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    if (error) {
      BOOL isConnectionError = [QNUtils isConnectionError:error];
      if (isConnectionError) {
        if (doneTryCount < 3) {
          doneTryCount++;
          [weakSelf dataTaskWithRequest:request tryCount:doneTryCount parseResponse:parseResponse completion:completion];
          
          return;
        } else {
          [weakSelf storeRequestIfNeeded:request];
        }
      }

      if (completion) {
        completion(nil, error);
      }
      
      return;
    }
    
    if (!completion) {
      return;
    }
    
    NSError *criticalError = [weakSelf criticalErrorFromResponse:response];
    if (criticalError) {
      completion(nil, criticalError);
      return;
    }
    
    NSError *responseError = [weakSelf internalErrorFromResponse:response];
    if (responseError) {
      completion(nil, responseError);
      return;
    }
    
    if ((!data || ![data isKindOfClass:NSData.class])) {
      completion(nil, [QONErrors errorWithCode:QONAPIErrorFailedReceiveData]);
      return;
    }

    NSError *jsonError;
    id dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];

    if (jsonError.code == kUnableToParseEmptyDataDefaultCode && !parseResponse) {
      completion(nil, nil);
      return;
    }

    if ((jsonError.code || !dict)) {
      completion(nil, [QONErrors errorWithCode:QONAPIErrorFailedParseResponse]);
      return;
    }

    NSError *apiError = [weakSelf.errorsMapper errorFromRequestResult:dict];

    if (apiError) {
      QONVERSION_LOG(@"❌ Request failed: %@, error: %@", request.URL, apiError);
      completion(nil, apiError);
      return;
    }

    completion(dict, nil);
  }] resume];
}

- (NSError *)internalErrorFromResponse:(NSURLResponse *)response {
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSHTTPURLResponse *httpURLResponse = (NSHTTPURLResponse *)response;
    
    if (httpURLResponse.statusCode >= kInternalServerErrorFirstCode && httpURLResponse.statusCode <= kInternalServerErrorLastCode) {
      NSMutableDictionary *userInfo = [NSMutableDictionary new];
      userInfo[NSLocalizedDescriptionKey] = kInternalServerError;
      NSError *error = [NSError errorWithDomain:QonversionErrorDomain code:httpURLResponse.statusCode userInfo:userInfo];
      
      return error;
    }
  }
  
  return nil;
}

- (NSError *)criticalErrorFromResponse:(NSURLResponse *)response {
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSHTTPURLResponse *httpURLResponse = (NSHTTPURLResponse *)response;
    NSInteger statusCode = httpURLResponse.statusCode;
    
    if ([self.criticalErrorCodes containsObject:@(statusCode)]) {
      NSMutableDictionary *userInfo = [NSMutableDictionary new];
      userInfo[NSLocalizedDescriptionKey] = kAccessDeniedError;
      NSError *error = [NSError errorWithDomain:QonversionErrorDomain code:statusCode userInfo:userInfo];
      
      return error;
    }
  }
  
  return nil;
}

- (void)removeStoredRequestForTransactionId:(NSString *)transactionId {
  NSMutableDictionary *storedRequests = [[self storedPurchasesRequests] mutableCopy];
  if (transactionId.length > 0) {
    storedRequests[transactionId] = nil;
  }
  
  [self storePurchaseRequests:storedRequests];
}

- (void)storePurchaseRequests:(NSDictionary *)requests {
  NSData *updatedStoredRequestsData = [QNKeyedArchiver archivedDataWithObject:[requests copy]];
  [self.localStorage storeObject:updatedStoredRequestsData forKey:kKeyQUserDefaultsStoredPurchasesRequests];
}

- (NSDictionary *)storedPurchasesRequests {
  NSData *storedRequestsData = [self.localStorage loadObjectForKey:kKeyQUserDefaultsStoredPurchasesRequests];
  NSDictionary *unarchivedData = [QNKeyedArchiver unarchiveObjectWithData:storedRequestsData] ?: @{};
  if (![unarchivedData isKindOfClass:[NSDictionary class]]) {
    unarchivedData = @{};
  }
  
  return unarchivedData;
}

- (void)storeRequestForRetry:(NSURLRequest *)request transactionId:(NSString *)transactionId {
  NSMutableDictionary *storedRequests = [[self storedPurchasesRequests] mutableCopy];
  storedRequests[transactionId] = request;
  
  [self storePurchaseRequests:storedRequests];
}

- (void)storeRequestIfNeeded:(NSURLRequest *)request {
  NSURLComponents *components = [NSURLComponents componentsWithString:request.URL.absoluteString];
  NSString *requestString = [components.path stringByReplacingOccurrencesOfString:@"/" withString:@"" options:NSCaseInsensitiveSearch range:(NSRange){0, 1}];
  if ([self.retriableRequests containsObject:requestString]) {
    NSData *storedRequestsData = [self.localStorage loadObjectForKey:kStoredRequestsKey];
    NSArray *unarchivedData = [QNKeyedArchiver unarchiveObjectWithData:storedRequestsData] ?: @[];
    NSMutableArray *storedRequests = [unarchivedData mutableCopy];
    [storedRequests addObject:request];
    
    NSData *updatedStoredRequestsData = [QNKeyedArchiver archivedDataWithObject:[storedRequests copy]];
    [self.localStorage storeObject:updatedStoredRequestsData forKey:kStoredRequestsKey];
  }
}

@end
