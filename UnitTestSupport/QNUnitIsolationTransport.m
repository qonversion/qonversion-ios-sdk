#import "QNUnitIsolationTransport.h"
#if QN_UNIT_TEST_ISOLATION
#import <objc/runtime.h>
#include <string.h>

NSInteger const QNUnitIsolationTransportVersion = 1;
NSString * const QNUnitIsolationErrorDomain = @"QNUnitIsolationDenied";

@interface QNUnitIsolationURLProtocol : NSURLProtocol
@end
@interface QNUnitIsolationTransport (ProtocolPrivate)
+ (nullable NSDictionary *)consumeRequest:(NSURLRequest *)request;
@end

static NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *fixtures;
static NSMutableArray<NSURLRequest *> *captured;
static NSHashTable *sessions;
static NSHashTable *mocks;
static BOOL activeCase;
static BOOL caseHasRun;
static NSUInteger denied, platformDenied, outsideCase, observers, expectedDenied, expectedPlatform;
static NSUInteger fixtureCount;
static NSTimeInterval caseDeadline;
static const NSUInteger limit = 64;

@implementation QNUnitIsolationTransport
+ (void)initialize {
  if (self != QNUnitIsolationTransport.class) return;
  fixtures = [NSMutableDictionary new];
  captured = [NSMutableArray new];
  sessions = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
  mocks = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
}
+ (NSError *)deniedError {
  // Deliberately outside the SDK's transient NSURLError retry codes. No request details.
  return [NSError errorWithDomain:QNUnitIsolationErrorDomain code:59991 userInfo:nil];
}
+ (NSError *)blockPlatformOperation {
  @synchronized(self) { platformDenied++; if (!activeCase) outsideCase++; }
  return self.deniedError;
}
+ (void)denyPlatformOperation {
  [self blockPlatformOperation];
  [NSException raise:@"QNUnitIsolationDenied" format:@"Unconfigured platform operation in unit isolation"];
}
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                 delegate:(id<NSURLSessionDelegate>)delegate queue:(NSOperationQueue *)queue {
  if (configuration.identifier != nil) [self denyPlatformOperation];
  NSURLSessionConfiguration *safe = [configuration copy];
  safe.protocolClasses = @[QNUnitIsolationURLProtocol.class];
  safe.URLCache = nil;
  safe.URLCredentialStorage = nil;
  safe.HTTPCookieStorage = nil;
  safe.HTTPShouldSetCookies = NO;
  safe.connectionProxyDictionary = @{};
  NSURLSession *session = [NSURLSession sessionWithConfiguration:safe delegate:delegate delegateQueue:queue];
  @synchronized(self) { [sessions addObject:session]; }
  return session;
}
+ (NSURLSession *)sharedSession {
  static NSURLSession *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ shared = [self sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration delegate:nil queue:nil]; });
  return shared;
}
+ (void)registerMemoryOnlyMock:(id)mock {
  // Only the existing OCMock class fake; no native NSURLSession can be whitelisted.
  BOOL accepted = NO;
  for (Class cls = object_getClass(mock); cls; cls = class_getSuperclass(cls)) {
    if (strcmp(class_getName(cls), "OCClassMockObject") == 0) accepted = YES;
  }
  if (!accepted) [self denyPlatformOperation];
  @synchronized(self) { [mocks addObject:mock]; }
}
+ (void)requireGuardedSession:(NSURLSession *)session {
  BOOL accepted;
  @synchronized(self) { accepted = [sessions containsObject:session] || [mocks containsObject:session]; }
  if (!accepted) [self denyPlatformOperation];
}
+ (void)beginCaseWithExpectedDenials:(NSUInteger)denials platformDenials:(NSUInteger)platformDenials {
  @synchronized(self) {
    // A fresh host process is mandatory for every fixture case. A generation on
    // current requests alone cannot identify a future callback from an old case.
    if (caseHasRun || activeCase || outsideCase != 0 || denials > limit || platformDenials > limit)
      [NSException raise:@"QNUnitIsolationLifecycle" format:@"Unit isolation case lifecycle invalid"];
    caseHasRun = YES; activeCase = YES; denied = 0; platformDenied = 0;
    caseDeadline = NSProcessInfo.processInfo.systemUptime + 15.0;
    expectedDenied = denials; expectedPlatform = platformDenials;
    fixtureCount = 0; [fixtures removeAllObjects]; [captured removeAllObjects];
  }
}
+ (BOOL)finishCase {
  // Caller first waits for its request completions. This snapshot detects current
  // leftovers, not future callbacks. No second case can begin in this process.
  NSArray *known;
  @synchronized(self) { known = sessions.allObjects; }
  dispatch_group_t group = dispatch_group_create();
  __block NSUInteger pending = 0;
  NSObject *lock = [NSObject new];
  for (NSURLSession *session in known) {
    dispatch_group_enter(group);
    [session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
      for (NSURLSessionTask *task in tasks) {
        if (task.state != NSURLSessionTaskStateCompleted) {
          @synchronized(lock) { pending++; }
          [task cancel];
        }
      }
      dispatch_group_leave(group);
    }];
  }
  BOOL drained = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0;
  @synchronized(self) {
    BOOL valid = activeCase && NSProcessInfo.processInfo.systemUptime <= caseDeadline && drained && pending == 0 && outsideCase == 0
      && denied == expectedDenied && platformDenied == expectedPlatform;
    activeCase = NO; [fixtures removeAllObjects]; [captured removeAllObjects]; fixtureCount = 0;
    return valid;
  }
}
+ (void)enqueueMethod:(NSString *)method URL:(NSURL *)URL status:(NSInteger)status
                data:(NSData *)data error:(NSError *)error {
  @synchronized(self) {
    NSString *scheme = URL.scheme.lowercaseString;
    if (!activeCase || fixtureCount >= limit || data.length > 1024 * 1024
        || ![@[@"http", @"https"] containsObject:scheme] || method.length == 0
        || status < 100 || status > 599)
      [NSException raise:@"QNUnitIsolationFixture" format:@"Invalid bounded unit fixture"];
    NSString *key = [NSString stringWithFormat:@"%@ %@", method, URL.absoluteString];
    NSMutableArray *queue = fixtures[key] ?: [NSMutableArray new];
    NSMutableDictionary *entry = [@{@"status": @(status), @"data": [data copy]} mutableCopy];
    if (error) entry[@"error"] = [NSError errorWithDomain:error.domain code:error.code userInfo:nil];
    [queue addObject:entry]; fixtures[key] = queue; fixtureCount++;
  }
}
+ (NSDictionary *)consumeRequest:(NSURLRequest *)request {
  @synchronized(self) {
    if (!activeCase) outsideCase++;
    if (!activeCase || NSProcessInfo.processInfo.systemUptime > caseDeadline || captured.count >= limit) { denied++; return nil; }
    [captured addObject:[request copy]];
    NSString *key = [NSString stringWithFormat:@"%@ %@", request.HTTPMethod ?: @"GET", request.URL.absoluteString];
    NSMutableArray *queue = fixtures[key];
    NSDictionary *entry = queue.firstObject;
    if (entry) { [queue removeObjectAtIndex:0]; fixtureCount--; }
    else denied++;
    return entry;
  }
}
+ (NSArray<NSURLRequest *> *)capturedRequests { @synchronized(self) { return [captured copy]; } }
+ (NSDictionary<NSString *, NSNumber *> *)aggregateCounts {
  @synchronized(self) { return @{@"denied": @(denied), @"platform_denied": @(platformDenied),
    @"outside_case": @(outsideCase), @"store_observers": @(observers), @"captured": @(captured.count),
    @"case_has_run": @(caseHasRun), @"active_case": @(activeCase)}; }
}
+ (void)recordStoreObserver { @synchronized(self) { observers++; } }
+ (NSString *)storefrontCountryCode { return @"ZZZ"; }
@end

@implementation QNUnitIsolationStoreQueue
+ (instancetype)sharedQueue {
  static QNUnitIsolationStoreQueue *queue; static dispatch_once_t once;
  dispatch_once(&once, ^{ queue = [self new]; }); return queue;
}
- (void)addTransactionObserver:(id)observer { [QNUnitIsolationTransport recordStoreObserver]; }
- (void)addPayment:(id)payment { [QNUnitIsolationTransport denyPlatformOperation]; }
- (void)presentCodeRedemptionSheet { [QNUnitIsolationTransport denyPlatformOperation]; }
- (void)restoreCompletedTransactions { [QNUnitIsolationTransport denyPlatformOperation]; }
- (void)finishTransaction:(id)transaction { /* synthetic transaction bookkeeping only */ }
@end

@implementation QNUnitIsolationURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (BOOL)canInitWithTask:(NSURLSessionTask *)task { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
  NSDictionary *entry = [QNUnitIsolationTransport consumeRequest:self.request];
  NSError *error = entry[@"error"];
  if (!entry || error) {
    [self.client URLProtocol:self didFailWithError:error ?: QNUnitIsolationTransport.deniedError];
    return;
  }
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
    statusCode:[entry[@"status"] integerValue] HTTPVersion:@"HTTP/1.1"
    headerFields:@{@"Content-Type": @"application/json"}];
  [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
  [self.client URLProtocol:self didLoadData:entry[@"data"]];
  [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
#endif
