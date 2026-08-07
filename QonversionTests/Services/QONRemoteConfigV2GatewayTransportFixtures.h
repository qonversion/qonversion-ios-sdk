//
//  Shared deterministic fakes for the Remote Config v2 gateway transport.
//
//  The file carries implementations on purpose so the XCTest suite and the
//  headless harness can share exactly one set of fakes. Include it from a
//  single translation unit per target.
//

#import <Foundation/Foundation.h>

#import "QONRemoteConfigV2GatewayTransport.h"
#import "QNLocalStorage.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Scripted HTTP

@interface QONRCV2ScriptedHTTPResponse : NSObject
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, strong, nullable) NSData *body;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, assign) BOOL isTransportError;
+ (instancetype)status:(NSInteger)status
                  body:(nullable NSData *)body
               headers:(nullable NSDictionary<NSString *, NSString *> *)headers;
+ (instancetype)transportError;
@end

@implementation QONRCV2ScriptedHTTPResponse
+ (instancetype)status:(NSInteger)status
                  body:(nullable NSData *)body
               headers:(nullable NSDictionary<NSString *, NSString *> *)headers {
  QONRCV2ScriptedHTTPResponse *response = [QONRCV2ScriptedHTTPResponse new];
  response.status = status;
  response.body = body;
  response.headers = headers;
  return response;
}
+ (instancetype)transportError {
  QONRCV2ScriptedHTTPResponse *response = [QONRCV2ScriptedHTTPResponse new];
  response.isTransportError = YES;
  return response;
}
@end

@interface QONRCV2FakeHTTPExecutor : NSObject <QONRemoteConfigV2HTTPExecuting>
@property (nonatomic, strong) NSMutableArray<QONRCV2ScriptedHTTPResponse *> *script;
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *requests;
- (void)enqueue:(QONRCV2ScriptedHTTPResponse *)response;
@end

@implementation QONRCV2FakeHTTPExecutor
- (instancetype)init {
  self = [super init];
  if (self) {
    _script = [NSMutableArray new];
    _requests = [NSMutableArray new];
  }
  return self;
}
- (void)enqueue:(QONRCV2ScriptedHTTPResponse *)response {
  [self.script addObject:response];
}
- (void)executeRequest:(NSURLRequest *)request
            completion:(QONRemoteConfigV2HTTPCompletion)completion {
  [self.requests addObject:request];
  QONRCV2ScriptedHTTPResponse *scripted = self.script.firstObject;
  if (scripted) [self.script removeObjectAtIndex:0];
  if (!scripted || scripted.isTransportError) {
    completion(nil, nil, [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorNotConnectedToInternet
                                         userInfo:nil]);
    return;
  }
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                           statusCode:scripted.status
                                                          HTTPVersion:@"HTTP/1.1"
                                                         headerFields:scripted.headers];
  completion(scripted.body, response, nil);
}
@end

#pragma mark - Storage and clock

@interface QONRCV2FakeLocalStorage : NSObject <QNLocalStorage>
@property (nonatomic, strong) NSMutableDictionary *objects;
@property (nonatomic, assign) BOOL ignoreWrites;
@end

@implementation QONRCV2FakeLocalStorage
- (instancetype)init {
  self = [super init];
  if (self) _objects = [NSMutableDictionary new];
  return self;
}
- (void)storeObject:(id)object forKey:(NSString *)key {
  if (!self.ignoreWrites) self.objects[key] = object;
}
- (id)loadObjectForKey:(NSString *)key { return self.objects[key]; }
- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion(self.objects[key]);
}
- (void)removeObjectForKey:(NSString *)key { [self.objects removeObjectForKey:key]; }
@end

@interface QONRCV2FakeClock : NSObject <QONRemoteConfigV2FetchClock>
@property (nonatomic, assign) int64_t now;
@end

@implementation QONRCV2FakeClock
- (int64_t)nowMilliseconds { return self.now; }
@end

#pragma mark - Client context

@interface QONRCV2FakeInstallDateProvider : NSObject <QONRemoteConfigV2DeviceInstallDateProviding>
@property (nonatomic, strong, nullable) NSNumber *seconds;
@end

@implementation QONRCV2FakeInstallDateProvider
- (nullable NSNumber *)deviceInstalledAtSeconds { return self.seconds; }
@end

#pragma mark - Builders

static NSString *const QONRCV2TestProjectToken = @"project-token-secret";
static NSString *const QONRCV2TestBaseURLString = @"https://gateway.test.example/";
static NSString *const QONRCV2TestAnonUID = @"anon-uid-1";
static NSString *const QONRCV2TestStrongETag =
    @"\"0000000000000000000000000000000000000000000000000000000000000001\"";

static QONRemoteConfigV2Scope *QONRCV2Scope(NSString *canonicalUserID) {
  return [[QONRemoteConfigV2Scope alloc] initWithProjectKey:@"project-key"
                                                environment:@"production"
                                            canonicalUserID:canonicalUserID];
}

static QONRemoteConfigV2DeviceClientContextProvider *QONRCV2ContextProvider(
    id<QONRemoteConfigV2DeviceInstallDateProviding> installDateProvider) {
  return [[QONRemoteConfigV2DeviceClientContextProvider alloc]
        initWithPlatform:@"iOS"
              appVersion:@"1.2.3"
               osVersion:@"17.4"
              sdkVersion:@"9.9.9"
                  locale:@"en_US"
             deviceModel:@"iPhone15,2"
     installDateProvider:installDateProvider];
}

static NSData *QONRCV2BootstrapBody(NSString *token, int64_t expiresAtSeconds) {
  NSString *json = [NSString stringWithFormat:
      @"{\"session_token\":\"%@\",\"project_id\":42,\"environment\":\"production\","
       "\"expires_at\":%lld}", token, expiresAtSeconds];
  return [json dataUsingEncoding:NSUTF8StringEncoding];
}

/**
 Deliberately non-canonical: unsorted keys, irregular whitespace and an escaped
 unicode sequence. Any re-serialization on the way to admission changes it.
 */
static NSData *QONRCV2NonCanonicalSnapshotBody(void) {
  NSString *json = @"{  \"schema\" : 1,\n  \"z_key\":\"\\u00e9\",\r\n"
                    "\"entries\" : [ { \"key\" :\"a\" } ] ,\"a_key\":  2.500 }";
  return [json dataUsingEncoding:NSUTF8StringEncoding];
}

static id QONRCV2JSONFromRequest(NSURLRequest *request) {
  if (!request.HTTPBody) return nil;
  return [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
}

static NSString *_Nullable QONRCV2Header(NSURLRequest *request, NSString *field) {
  return [request valueForHTTPHeaderField:field];
}

static BOOL QONRCV2DataIdenticalBytes(NSData *_Nullable left, NSData *_Nullable right) {
  if (!left || !right) return NO;
  if (left.length != right.length) return NO;
  return memcmp(left.bytes, right.bytes, left.length) == 0;
}

NS_ASSUME_NONNULL_END
