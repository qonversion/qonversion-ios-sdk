#import "QNAPIClient.h"
#import "QNConstants.h"
#import "QNRequestBuilder.h"
#import "QNRequestSerializer.h"
#import "QNErrors.h"
#import "QNUtils.h"
#import "QNUserInfo.h"
#import "QNAPIConstants.h"
#import "QNInternalConstants.h"
#import "QNConstants.h"
#import "QNProductPurchaseModel.h"
#import "QNOffering.h"
#import "QNExperimentInfo.h"
#import "QNExperimentGroup.h"
#import "QNErrorsMapper.h"
#import "QNKeyedArchiver.h"

@interface QNAPIClient()

@property (nonatomic, strong) QNRequestSerializer *requestSerializer;
@property (nonatomic, strong) QNRequestBuilder *requestBuilder;
@property (nonatomic, strong) QNErrorsMapper *errorsMapper;
@property (nonatomic, copy) NSArray<NSString *> *retriableRequests;
@property (nonatomic, copy) NSArray<NSNumber *> *criticalErrorCodes;
@property (nonatomic, strong) NSError *criticalError;

@end

@implementation QNAPIClient

- (instancetype)init {
  self = super.init;
  if (self) {
    _requestSerializer = [[QNRequestSerializer alloc] init];
    _requestBuilder = [[QNRequestBuilder alloc] init];
    _errorsMapper = [QNErrorsMapper new];
    
    _apiKey = @"";
    _userID = @"";
    _debug = NO;
    _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    _retriableRequests = @[kInitEndpoint, kPurchaseEndpoint, kAttributionEndpoint];
    _criticalErrorCodes = @[@(401), @(402), @(403)];
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

- (void)setDebug:(BOOL)debug {
  _debug = debug;
  [self.requestBuilder setApiKey:[self obtainApiKey]];
}

- (void)processRequest:(NSURLRequest *)request completion:(QNAPIClientCompletionHandler)completion {
  [self dataTaskWithRequest:request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    if (!self.criticalError && error && [self.criticalErrorCodes containsObject:@(error.code)]) {
      self.criticalError = error;
    }
    
    if (completion) {
      completion(dict, error);
    }
  }];
}

// MARK: - Public

- (void)sendPushToken:(void (^)(BOOL success))completion {
  NSDictionary *data = [self.requestSerializer pushTokenData];
  data = [self enrichPushTokenData:data];
  NSURLRequest *request = [self.requestBuilder makeSendPushTokenRequestWith:data];
  
  [self processRequest:request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    BOOL isSuccess = error == nil;
    completion(isSuccess);
  }];
}

- (void)launchRequest:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion {
  NSDictionary *launchData = [self enrichParameters:[self.requestSerializer launchData]];
  NSURLRequest *request = [self.requestBuilder makeInitRequestWith:launchData];
  [self processRequest:request completion:completion];
}

- (NSURLRequest *)purchaseRequestWith:(SKProduct *)product
                          transaction:(SKPaymentTransaction *)transaction
                              receipt:(nullable NSString *)receipt
                        purchaseModel:(nullable QNProductPurchaseModel *)purchaseModel
                           completion:(QNAPIClientCompletionHandler)completion {
  NSDictionary *body = [self.requestSerializer purchaseData:product transaction:transaction receipt:receipt purchaseModel:purchaseModel];
  NSDictionary *resultData = [self enrichParameters:body];
  
  NSURLRequest *request = [self.requestBuilder makePurchaseRequestWith:resultData];
  
  [self processRequest:request completion:completion];
  
  return [request copy];
}

- (void)checkTrialIntroEligibilityParamsForProducts:(NSArray<QNProduct *> *)products
                                         completion:(QNAPIClientCompletionHandler)completion {
  NSDictionary *requestData = [self.requestSerializer introTrialEligibilityDataForProducts:products];
  NSDictionary *resultBody = [self enrichParameters:requestData];
  NSURLRequest *request = [self.requestBuilder makeIntroTrialEligibilityRequestWithData:resultBody];
  
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)properties:(NSDictionary *)properties completion:(QNAPIClientCompletionHandler)completion {
  NSDictionary *body = [self enrichParameters:@{@"properties": properties}];
  NSURLRequest *request = [self.requestBuilder makePropertiesRequestWith:body];
  
  [self processRequest:request completion:completion];
}

- (void)userActionPointsWithCompletion:(QNAPIClientCompletionHandler)completion {
  NSURLRequest *request = [self.requestBuilder makeUserActionPointsRequestWith:self.userID];
  
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)automationWithID:(NSString *)automationID completion:(QNAPIClientCompletionHandler)completion {
  NSURLRequest *request = [self.requestBuilder makeScreensRequestWith:automationID];
  
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)userInfoRequestWithID:(NSString *)userID completion:(QNAPIClientCompletionHandler)completion {
  NSURLRequest *request = [self.requestBuilder makeUserInfoRequestWithID:userID apiKey:[self obtainApiKey]];
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)createIdentityForUserID:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNAPIClientCompletionHandler)completion {
  NSDictionary *parameters = @{@"anon_id": anonUserID, @"identity_id": userID};
  NSURLRequest *request = [self.requestBuilder makeCreateIdentityRequestWith:parameters];
  
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)trackScreenShownWithID:(NSString *)automationID {
  NSDictionary *body = @{@"user": self.userID};
  NSURLRequest *request = [self.requestBuilder makeScreenShownRequestWith:automationID body:body];
  
  return [self dataTaskWithRequest:request completion:nil];
}

- (void)attributionRequest:(QNAttributionProvider)provider
                      data:(NSDictionary *)data
                completion:(QNAPIClientCompletionHandler)completion {
  NSDictionary *body = [self.requestSerializer attributionDataWithDict:data fromProvider:provider];
  NSDictionary *resultData = [self enrichParameters:body];
  NSURLRequest *request = [[self requestBuilder] makeAttributionRequestWith:resultData];
  [self processRequest:request completion:completion];
}

- (void)processStoredRequests {
  NSData *storedRequestsData = [[NSUserDefaults standardUserDefaults] valueForKey:kStoredRequestsKey];
  NSArray *storedRequests = [QNKeyedArchiver unarchiveObjectWithData:storedRequestsData];
  
  if (![storedRequests isKindOfClass:[NSArray class]]) {
    [[NSUserDefaults standardUserDefaults] setValue:nil forKey:kStoredRequestsKey];
  } else {
    for (NSInteger i = 0; i < [storedRequests count]; i++) {
      if ([storedRequests[i] isKindOfClass:[NSURLRequest class]]) {
        NSURLRequest *request = storedRequests[i];
        
        [self dataTaskWithRequest:request completion:nil];
      }
    }
    
    [[NSUserDefaults standardUserDefaults] setValue:nil forKey:kStoredRequestsKey];
  }
  
  [self processStorePurchasesRequests];
}

- (void)processStorePurchasesRequests {
  NSDictionary *unarchivedData = [self storedPurchasesRequests];
  
  for (NSString *transactionId in unarchivedData.allKeys) {
    NSURLRequest *request = unarchivedData[transactionId];
    if ([request isKindOfClass:[NSURLRequest class]]) {
      [self dataTaskWithRequest:request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
        if (![QNUtils shouldPurchaseRequestBeRetried:error]) {
          [self removeStoredRequestForTransactionId:transactionId];
        }
      }];
    }
  }
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
  
  [baseDict setObject:_userID forKey:@"q_uid"];
  [baseDict setObject:_userID forKey:@"client_uid"];
  [baseDict setObject:keyQVersion forKey:@"version"];
  [baseDict setObject:@(self.debug) forKey:@"debug_mode"];
  
  return [baseDict copy];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request
                 completion:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion {
  if (self.criticalError && completion) {
    completion(nil, self.criticalError);
    return;
  }
  
  [self dataTaskWithRequest:request tryCount:0 completion:completion];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request
                   tryCount:(NSInteger)tryCount
                 completion:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion {
  __block NSInteger doneTryCount = tryCount;
  
  __block __weak QNAPIClient *weakSelf = self;
  [[self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    if (error) {
      BOOL isConnectionError = [QNUtils isConnectionError:error];
      if (isConnectionError) {
        if (doneTryCount < 3) {
          doneTryCount++;
          [weakSelf dataTaskWithRequest:request tryCount:doneTryCount completion:completion];
          
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
      completion(nil, [QNErrors errorWithCode:QNAPIErrorFailedReceiveData]);
      return;
    }
    
    NSError *jsonError;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
    
    if ((jsonError.code || !dict)) {
      completion(nil, [QNErrors errorWithCode:QNAPIErrorFailedParseResponse]);
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
      NSError *error = [NSError errorWithDomain:keyQNErrorDomain code:httpURLResponse.statusCode userInfo:userInfo];
      
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
      NSError *error = [NSError errorWithDomain:keyQNErrorDomain code:statusCode userInfo:userInfo];
      
      return error;
    }
  }
  
  return nil;
}

- (void)removeStoredRequestForTransactionId:(NSString *)transactionId {
  NSMutableDictionary *storedRequests = [[self storedPurchasesRequests] mutableCopy];
  storedRequests[transactionId] = nil;
  
  [self storePurchaseRequests:storedRequests];
}

- (void)storePurchaseRequests:(NSDictionary *)requests {
  NSData *updatedStoredRequestsData = [QNKeyedArchiver archivedDataWithObject:[requests copy]];
  [[NSUserDefaults standardUserDefaults] setValue:updatedStoredRequestsData forKey:kKeyQUserDefaultsStoredPurchasesRequests];
}

- (NSDictionary *)storedPurchasesRequests {
  NSData *storedRequestsData = [[NSUserDefaults standardUserDefaults] valueForKey:kKeyQUserDefaultsStoredPurchasesRequests];
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
    NSData *storedRequestsData = [[NSUserDefaults standardUserDefaults] valueForKey:kStoredRequestsKey];
    NSArray *unarchivedData = [QNKeyedArchiver unarchiveObjectWithData:storedRequestsData] ?: @[];
    NSMutableArray *storedRequests = [unarchivedData mutableCopy];
    [storedRequests addObject:request];
    
    NSData *updatedStoredRequestsData = [QNKeyedArchiver archivedDataWithObject:[storedRequests copy]];
    [[NSUserDefaults standardUserDefaults] setValue:updatedStoredRequestsData forKey:kStoredRequestsKey];
  }
}

- (void)sendOfferingEvent:(QNOffering *)offering {
  NSMutableDictionary *payload = [NSMutableDictionary new];
  payload[@"experiment_id"] = offering.experimentInfo.identifier;
  
  NSURLRequest *request = [self.requestBuilder makeEventRequestWithEventName:kKeyQExperimentStartedEventName payload:[payload copy] userID:self.userID];
  
  return [self dataTaskWithRequest:request completion:nil];
}

@end
