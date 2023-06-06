#import "Foundation/Foundation.h"
#import "QONLaunchResult.h"

@class SKProduct, SKPaymentTransaction, QNProductPurchaseModel, QONOffering, QONProduct, QONStoreKit2PurchaseModel;

typedef void (^QNAPIClientCompletionHandler)(NSDictionary * _Nullable dict, NSError * _Nullable error);

NS_ASSUME_NONNULL_BEGIN

@interface QNAPIClient : NSObject

+ (instancetype)shared;

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, assign) BOOL debug;

- (void)setSDKVersion:(NSString *)version;
- (void)setBaseURL:(NSString *)url;
- (void)launchRequest:(QNAPIClientCompletionHandler)completion;
- (void)sendPushToken:(void (^)(BOOL success))completion;

- (NSURLRequest *)purchaseRequestWith:(SKProduct *)product
                          transaction:(SKPaymentTransaction *)transaction
                              receipt:(nullable NSString *)receipt
                        purchaseModel:(nullable QNProductPurchaseModel *)purchaseModel
                           completion:(QNAPIClientCompletionHandler)completion;
- (NSURLRequest *)purchaseRequestWith:(NSDictionary *) body
                           completion:(QNAPIClientCompletionHandler)completion;

- (void)checkTrialIntroEligibilityParamsForProducts:(NSArray<QONProduct *> *)products
                                         completion:(QNAPIClientCompletionHandler)completion;
- (void)checkTrialIntroEligibilityParamsForData:(NSDictionary *)data
                                     completion:(QNAPIClientCompletionHandler)completion;

- (void)properties:(NSDictionary *)properties completion:(QNAPIClientCompletionHandler)completion;
- (void)userActionPointsWithCompletion:(QNAPIClientCompletionHandler)completion;
- (void)automationWithID:(NSString *)automationID completion:(QNAPIClientCompletionHandler)completion;
- (void)trackScreenShownWithID:(NSString *)automationID;
- (void)trackScreenShownWithID:(NSString *)automationID completion:(QNAPIClientCompletionHandler)completion;
- (void)userInfoRequestWithID:(NSString *)userID completion:(QNAPIClientCompletionHandler)completion;

- (void)createIdentityForUserID:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNAPIClientCompletionHandler)completion;

- (void)attributionRequest:(QONAttributionProvider)provider
                      data:(NSDictionary *)data
                completion:(QNAPIClientCompletionHandler)completion;
- (void)processStoredRequests;
- (void)sendOfferingEvent:(QONOffering *)offering;
- (void)storeRequestForRetry:(NSURLRequest *)request transactionId:(NSString *)transactionId;
- (void)removeStoredRequestForTransactionId:(NSString *)transactionId;
- (NSURLRequest *)handlePurchase:(QONStoreKit2PurchaseModel *)purchaseInfo
                         receipt:(nullable NSString *)receipt
                      completion:(QNAPIClientCompletionHandler)completion;
- (void)sendCrashReport:(NSDictionary *)data completion:(QNAPIClientCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
