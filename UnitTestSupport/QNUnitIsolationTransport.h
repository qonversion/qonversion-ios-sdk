#import <Foundation/Foundation.h>

#if QN_UNIT_TEST_ISOLATION
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSInteger const QNUnitIsolationTransportVersion;
FOUNDATION_EXPORT NSString * const QNUnitIsolationErrorDomain;

// Test-only. No runtime switch can enable native networking.
@interface QNUnitIsolationTransport : NSObject
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                 delegate:(nullable id<NSURLSessionDelegate>)delegate
                                    queue:(nullable NSOperationQueue *)queue NS_SWIFT_NAME(session(configuration:delegate:queue:));
+ (NSURLSession *)sharedSession NS_SWIFT_NAME(sharedSession());
+ (void)requireGuardedSession:(NSURLSession *)session NS_SWIFT_NAME(requireGuarded(_:));
+ (void)registerMemoryOnlyMock:(id)mock;
// Exactly one case per host process; finishCase never permits another beginCase.
+ (void)beginCaseWithExpectedDenials:(NSUInteger)denials platformDenials:(NSUInteger)platformDenials NS_SWIFT_NAME(beginCase(expectedDenials:platformDenials:));
+ (BOOL)finishCase;
+ (void)enqueueMethod:(NSString *)method URL:(NSURL *)URL status:(NSInteger)status
                data:(NSData *)data error:(nullable NSError *)error;
+ (NSArray<NSURLRequest *> *)capturedRequests;
+ (NSDictionary<NSString *, NSNumber *> *)aggregateCounts;
+ (NSError *)deniedError NS_SWIFT_NAME(deniedError());
+ (void)denyPlatformOperation NS_SWIFT_NAME(denyPlatformOperation());
+ (NSError *)blockPlatformOperation NS_SWIFT_NAME(blockPlatformOperation());
+ (void)recordStoreObserver;
+ (NSString *)storefrontCountryCode NS_SWIFT_NAME(storefrontCountryCode());
@end
// In-memory StoreKit queue. No StoreKit class is instantiated by this adapter.
@interface QNUnitIsolationStoreQueue : NSObject
+ (instancetype)sharedQueue;
- (void)addTransactionObserver:(id)observer;
- (void)addPayment:(id)payment;
- (void)presentCodeRedemptionSheet;
- (void)restoreCompletedTransactions;
- (void)finishTransaction:(id)transaction;
@end
NS_ASSUME_NONNULL_END
#endif
