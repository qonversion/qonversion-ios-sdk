#import "QNAPIClient.h"
#import "QNRequestBuilder.h"
#import "QNRequestSerializer.h"
#import "QNDevice.h"
#import "QNMapper.h"
#import "QNConstants.h"
#import "QNErrors.h"

@interface QNAPIClient()

@property (nonatomic, strong) QNDevice *device;
@property (nonatomic, strong) QNRequestSerializer *requestSerializer;
@property (nonatomic, strong) QNRequestBuilder *requestBuilder;

@end

@implementation QNAPIClient

- (instancetype)init {
  self = super.init;
  if (self) {
    _requestSerializer = [[QNRequestSerializer alloc] init];
    _requestBuilder = [[QNRequestBuilder alloc] init];
    
    _apiKey = @"";
    _userID = @"";
    _device = QNDevice.current;
    _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
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

- (void)launch:(void (^)(QNLaunchResult * _Nullable result, NSError * _Nullable error))completion {
  NSDictionary *launchData = [self enrichParameters:[_requestSerializer launchData]];
  NSURLRequest *request = [[self requestBuilder] makeInitRequestWith:launchData];
  
  [self dataTaskWithRequest:request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    if (dict) {
      //[QNMapper ]
    }
  }];
}

// MARK: - Private

- (NSDictionary *)enrichParameters:(NSDictionary *)parameters {
  NSDictionary *_parameters = parameters ?: @{};
  
  NSMutableDictionary *baseDict = [[NSMutableDictionary alloc] initWithDictionary:_parameters];
  [baseDict setObject:_apiKey forKey:@"access_token"];
  
  [baseDict setObject:@"qonversion_user_id" forKey:@"q_uid"];
  [baseDict setObject:_userID forKey:@"client_uid"];
  [baseDict setObject:keyQVersion forKey:@"version"];
  
  return [baseDict copy];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request
                 completion:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion {
  [[self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    
    if (error) {
      completion(nil, error);
      return;
    }
  
    if (!data || ![data isKindOfClass:NSData.class]) {
      completion(nil, [QNErrors errorWithCode:QNAPIErrorFailedReceiveData]);
      return;
    }
    
    NSError *jsonError = [[NSError alloc] init];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
    
    if (jsonError.code || !dict) {
      completion(nil, [QNErrors errorWithCode:QNAPIErrorFailedParseResponse]);
      return;
    }
    
    completion(dict, nil);
  }] resume];
}

@end
