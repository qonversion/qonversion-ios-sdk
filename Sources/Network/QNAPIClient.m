#import "QNAPIClient.h"
#import "QNRequestBuilder.h"
#import "QNRequestSerializer.h"
#import "QNDevice.h"
#import "QNMapper.h"

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
    
    _device = [[QNDevice alloc] init];
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
