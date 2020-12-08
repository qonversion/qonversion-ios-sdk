#import "QNAPIClient.h"
#import "QNConstants.h"
#import "QNRequestBuilder.h"
#import "QNRequestSerializer.h"
#import "QNDevice.h"
#import "QNMapper.h"
#import "QNErrors.h"
#import "QNMapperObject.h"
#import "QNUtils.h"
#import "QNUserInfo.h"
#import "QNAPIConstants.h"

@interface QNAPIClient()

@property (nonatomic, strong) QNDevice *device;
@property (nonatomic, strong) QNRequestSerializer *requestSerializer;
@property (nonatomic, strong) QNRequestBuilder *requestBuilder;
@property (nonatomic, copy) NSArray<NSNumber *> *connectionErrorCodes;
@property (nonatomic, copy) NSArray<NSString *> *retriableRequests;

@end

@implementation QNAPIClient

- (instancetype)init {
  self = super.init;
  if (self) {
    _requestSerializer = [[QNRequestSerializer alloc] init];
    _requestBuilder = [[QNRequestBuilder alloc] init];
    
    _apiKey = @"";
    _userID = @"";
    _debug = NO;
    _device = QNDevice.current;
    _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    _connectionErrorCodes = @[
      @(NSURLErrorNotConnectedToInternet),
      @(NSURLErrorCallIsActive),
      @(NSURLErrorNetworkConnectionLost),
      @(NSURLErrorDataNotAllowed),
      @(NSURLErrorTimedOut)
    ];
    _retriableRequests = @[kInitEndpoint, kPurchaseEndpoint, kPropertiesEndpoint, kAttributionEndpoint];
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

// MARK: - Public

- (void)launchRequest:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion {
  NSDictionary *launchData = [self enrichParameters:[self.requestSerializer launchData]];
  NSURLRequest *request = [self.requestBuilder makeInitRequestWith:launchData];
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)purchaseRequestWith:(SKProduct *)product
                transaction:(SKPaymentTransaction *)transaction
                    receipt:(nullable NSString *)receipt
                 completion:(QNAPIClientCompletionHandler)completion {
  NSDictionary *body = [self.requestSerializer purchaseData:product transaction:transaction receipt:receipt];
  NSDictionary *resultData = [self enrichParameters:body];
  
  NSURLRequest *request = [self.requestBuilder makePurchaseRequestWith:resultData];
  
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)properties:(NSDictionary *)properties completion:(QNAPIClientCompletionHandler)completion {
  NSDictionary *body = [self enrichParameters:@{@"properties": properties}];
  NSURLRequest *request = [self.requestBuilder makePropertiesRequestWith:body];
  
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)attributionRequest:(QNAttributionProvider)provider
                      data:(NSDictionary *)data
                completion:(QNAPIClientCompletionHandler)completion {
  NSDictionary *body = [self.requestSerializer attributionDataWithDict:data fromProvider:provider];
  NSDictionary *resultData = [self enrichParameters:body];
  NSURLRequest *request = [[self requestBuilder] makeAttributionRequestWith:resultData];
  return [self dataTaskWithRequest:request completion:completion];
}

- (void)processStoredRequests {
  NSData *storedRequestsData = [[NSUserDefaults standardUserDefaults] valueForKey:kStoredRequestsKey];
  NSArray *storedRequests = [NSKeyedUnarchiver unarchiveObjectWithData:storedRequestsData];
  
  if (![storedRequests isKindOfClass:[NSArray class]]) {
    [[NSUserDefaults standardUserDefaults] setValue:nil forKey:kStoredRequestsKey];
    return;
  }
  
  for (NSInteger i = 0; i < [storedRequests count]; i++) {
    if ([storedRequests[i] isKindOfClass:[NSURLRequest class]]) {
      NSURLRequest *request = storedRequests[i];
      
      [self dataTaskWithRequest:request completion:nil];
    }
  }
  
  [[NSUserDefaults standardUserDefaults] setValue:nil forKey:kStoredRequestsKey];
}

// MARK: - Private

- (NSDictionary *)enrichParameters:(NSDictionary *)parameters {
  NSDictionary *_parameters = parameters ?: @{};
  
  NSMutableDictionary *baseDict = [[NSMutableDictionary alloc] initWithDictionary:_parameters];
  [baseDict setObject:_apiKey forKey:@"access_token"];
  
  [baseDict setObject:_userID forKey:@"q_uid"];
  [baseDict setObject:_userID forKey:@"client_uid"];
  [baseDict setObject:keyQVersion forKey:@"version"];
  [baseDict setObject:[NSNumber numberWithBool:[QNUserInfo isDebug]] forKey:@"debug_mode"];
  
  return [baseDict copy];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request
                 completion:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion {
  [self dataTaskWithRequest:request tryCount:0 completion:completion];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request
                   tryCount:(NSInteger)tryCount
                 completion:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion {
  __block NSInteger doneTryCount = tryCount;
  
  __block __weak QNAPIClient *weakSelf = self;
  [[self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    if (error) {
      BOOL isConnectionError = [weakSelf.connectionErrorCodes containsObject:@(error.code)];
      if (isConnectionError) {
        if (doneTryCount < 3) {
          doneTryCount++;
          [weakSelf dataTaskWithRequest:request tryCount:doneTryCount completion:completion];
          
          return;
        } else {
          [weakSelf storeRequestIfNeeded:request];
        }
      }
      
      completion(nil, error);
      return;
    }
    
    if ((!data || ![data isKindOfClass:NSData.class]) && completion) {
      completion(nil, [QNErrors errorWithCode:QNAPIErrorFailedReceiveData]);
      return;
    }
    
    NSError *jsonError = [[NSError alloc] init];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
    
    if ((jsonError.code || !dict) && completion) {
      completion(nil, [QNErrors errorWithCode:QNAPIErrorFailedParseResponse]);
      return;
    }
    
    if (completion) {
      completion(dict, nil);
    }
  }] resume];
}

- (void)storeRequestIfNeeded:(NSURLRequest *)request {
  NSURLComponents *components = [NSURLComponents componentsWithString:request.URL.absoluteString];
  NSString *requestString = [components.path stringByReplacingOccurrencesOfString:@"/" withString:@"" options:NSCaseInsensitiveSearch range:(NSRange){0, 1}];
  if ([self.retriableRequests containsObject:requestString]) {
    NSData *storedRequestsData = [[NSUserDefaults standardUserDefaults] valueForKey:kStoredRequestsKey];
    NSArray *unarchivedData = [NSKeyedUnarchiver unarchiveObjectWithData:storedRequestsData] ?: @[];
    NSMutableArray *storedRequests = [unarchivedData mutableCopy];
    [storedRequests addObject:request];
    NSData *updatedStoredRequestsData = [NSKeyedArchiver archivedDataWithRootObject:[storedRequests copy]];
    [[NSUserDefaults standardUserDefaults] setValue:updatedStoredRequestsData forKey:kStoredRequestsKey];
  }
}

@end
