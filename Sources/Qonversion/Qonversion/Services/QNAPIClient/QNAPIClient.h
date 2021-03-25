#import "Foundation/Foundation.h"
#import "QNLaunchResult.h"

@class SKProduct, SKPaymentTransaction;

typedef void (^QNAPIClientCompletionHandler)(NSDictionary * _Nullable dict, NSError * _Nullable error);

NS_ASSUME_NONNULL_BEGIN

@interface QNAPIClient : NSObject

+ (instancetype)shared;

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, assign) BOOL debug;

- (void)launchRequest:(QNAPIClientCompletionHandler)completion;

- (void)purchaseRequestWith:(SKProduct *)product
                transaction:(SKPaymentTransaction *)transaction
                    receipt:(nullable NSString *)receipt
                 completion:(QNAPIClientCompletionHandler)completion;

- (void)checkTrialIntroEligibilityParamsForProducts:(NSArray<QNProduct *> *)products
                                         completion:(QNAPIClientCompletionHandler)completion;

- (void)properties:(NSDictionary *)properties completion:(QNAPIClientCompletionHandler)completion;
- (void)userActionPointsWithCompletion:(QNAPIClientCompletionHandler)completion;
- (void)automationWithID:(NSString *)automationID completion:(QNAPIClientCompletionHandler)completion;
- (void)trackScreenShownWithID:(NSString *)automationID;

- (void)checkIdentityForUserID:(NSString *)userID completion:(QNAPIClientCompletionHandler)completion;
- (void)createIdentityForUserID:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNAPIClientCompletionHandler)completion;

- (void)attributionRequest:(QNAttributionProvider)provider
                      data:(NSDictionary *)data
                completion:(QNAPIClientCompletionHandler)completion;
- (void)processStoredRequests;

@end

NS_ASSUME_NONNULL_END
