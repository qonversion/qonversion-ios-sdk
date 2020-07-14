#import "QNAPIClient.h"
#import "QNRequestBuilder.h"
#import "QNRequestSerializer.h"
#import "QNDevice.h"
#import "QNMapper.h"
#import "QNConstants.h"

// Models
#import "QNLaunchResult+Protected.h"

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
    
    _device = QNDevice.current;
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
  
}

// MARK: - Private

- (NSDictionary *)enrichParameters:(NSDictionary *)parameters {
  NSDictionary *_parameters = parameters ?: @{};
  
  NSMutableDictionary *baseDict = [[NSMutableDictionary alloc] initWithDictionary:_parameters];
  [baseDict setObject:_apiKey forKey:@"access_token"];
  
  // TODO
  // Replace after tests
  [baseDict setObject:@"qonversion_user_id" forKey:@"q_uid"];
  [baseDict setObject:_userID forKey:@"client_uid"];
  [baseDict setObject:keyQVersion forKey:@"version"];
  
  return [baseDict copy];
}

- (NSURLSession *)session {
  return [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
}

- (void)dataTaskWithRequest:(NSURLRequest *)request completion:(void (^)(NSDictionary *dict))completion {
  NSURLSession *session = [[self session] copy];
  [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    if (!data || ![data isKindOfClass:NSData.class]) {
      return;
    }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!dict || ![dict respondsToSelector:@selector(valueForKey:)]) {
      return;
    }
    completion(dict);
  }] resume];
}

@end
