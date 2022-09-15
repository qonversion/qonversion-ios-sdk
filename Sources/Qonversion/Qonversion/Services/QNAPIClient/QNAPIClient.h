#import "Foundation/Foundation.h"
#import "QNLaunchResult.h"

@class SKProduct, SKPaymentTransaction, QNProductPurchaseModel, QNOffering;

typedef void (^QNAPIClientCompletionHandler)(NSDictionary * _Nullable dict, NSError * _Nullable error);

NS_ASSUME_NONNULL_BEGIN

@interface QNAPIClient : NSObject

+ (instancetype)shared;

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, assign) BOOL debug;

- (void)launchRequest:(QNAPIClientCompletionHandler)completion;
- (void)sendPushToken:(void (^)(BOOL success))completion;

- (NSURLRequest *)purchaseRequestWith:(SKProduct *)product
                          transaction:(SKPaymentTransaction *)transaction
                              receipt:(nullable NSString *)receipt
                        purchaseModel:(nullable QNProductPurchaseModel *)purchaseModel
                           completion:(QNAPIClientCompletionHandler)completion;

- (void)checkTrialIntroEligibilityParamsForProducts:(NSArray<QNProduct *> *)products
                                         completion:(QNAPIClientCompletionHandler)completion;

- (void)properties:(NSDictionary *)properties completion:(QNAPIClientCompletionHandler)completion;
- (void)userActionPointsWithCompletion:(QNAPIClientCompletionHandler)completion;
- (void)automationWithID:(NSString *)automationID completion:(QNAPIClientCompletionHandler)completion;
- (void)trackScreenShownWithID:(NSString *)automationID;
- (void)userInfoRequestWithID:(NSString *)userID completion:(QNAPIClientCompletionHandler)completion;

- (void)createIdentityForUserID:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNAPIClientCompletionHandler)completion;

- (void)attributionRequest:(QNAttributionProvider)provider
                      data:(NSDictionary *)data
                completion:(QNAPIClientCompletionHandler)completion;
- (void)processStoredRequests;
- (void)sendOfferingEvent:(QNOffering *)offering;
- (void)storeRequestForRetry:(NSURLRequest *)request transactionId:(NSString *)transactionId;
- (void)removeStoredRequestForTransactionId:(NSString *)transactionId;

@end

NS_ASSUME_NONNULL_END
