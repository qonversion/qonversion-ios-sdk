#import "Foundation/Foundation.h"
#import "QONLaunchResult.h"
#import "QONRequestTrigger.h"

@protocol QNLocalStorage;
@class SKProduct, SKProductDiscount, SKPaymentTransaction, QONOffering, QONProduct, QONStoreKit2PurchaseModel, QONPurchaseOptions, QNRequestSerializer;

typedef void (^QNAPIClientEmptyCompletionHandler)(NSError * _Nullable error);
typedef void (^QNAPIClientDictCompletionHandler)(NSDictionary * _Nullable dict, NSError * _Nullable error);
typedef void (^QNAPIClientArrayCompletionHandler)(NSArray * _Nullable array, NSError * _Nullable error);
typedef void (^QNAPIClientCommonCompletionHandler)(id _Nullable data, NSError * _Nullable error);

NS_ASSUME_NONNULL_BEGIN

@interface QNAPIClient : NSObject

+ (instancetype)shared;

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, strong) id<QNLocalStorage> localStorage;
@property (nonatomic, strong) QNRequestSerializer *requestSerializer;

- (void)setSDKVersion:(NSString *)version;
- (void)setBaseURL:(NSString *)url;
- (void)launchRequest:(QONRequestTrigger)requestTrigger
           completion:(QNAPIClientDictCompletionHandler)completion;

- (NSURLRequest *)purchaseRequestWith:(SKProduct *)product
                          transaction:(SKPaymentTransaction *)transaction
                              receipt:(nullable NSString *)receipt
                      purchaseOptions:(nullable QONPurchaseOptions *)purchaseOptions
                       requestTrigger:(QONRequestTrigger)requestTrigger
                           completion:(QNAPIClientDictCompletionHandler)completion;
- (NSURLRequest *)purchaseRequestWith:(NSDictionary *) body
                       requestTrigger:(QONRequestTrigger)requestTrigger
                           completion:(QNAPIClientDictCompletionHandler)completion;

- (void)checkTrialIntroEligibilityParamsForProducts:(NSArray<QONProduct *> *)products
                                         completion:(QNAPIClientDictCompletionHandler)completion;
- (void)checkTrialIntroEligibilityParamsForData:(NSDictionary *)data
                                     completion:(QNAPIClientDictCompletionHandler)completion;

- (void)sendProperties:(NSDictionary *)properties completion:(QNAPIClientDictCompletionHandler)completion;
- (void)getProperties:(QNAPIClientArrayCompletionHandler)completion;
- (void)userActionPointsWithCompletion:(QNAPIClientDictCompletionHandler)completion;
- (void)automationWithID:(NSString *)automationID completion:(QNAPIClientDictCompletionHandler)completion;
- (void)trackScreenShownWithID:(NSString *)automationID;
- (void)trackScreenShownWithID:(NSString *)automationID completion:(QNAPIClientDictCompletionHandler)completion;
- (void)userInfoRequestWithID:(NSString *)userID completion:(QNAPIClientDictCompletionHandler)completion;

- (void)createIdentityForUserID:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNAPIClientDictCompletionHandler)completion;

- (void)attributionRequest:(QONAttributionProvider)provider
                      data:(NSDictionary *)data
                completion:(QNAPIClientDictCompletionHandler)completion;
- (void)processStoredRequests;
- (void)storeRequestForRetry:(NSURLRequest *)request transactionId:(NSString *)transactionId;
- (void)removeStoredRequestForTransactionId:(NSString *)transactionId;
- (void)loadRemoteConfig:(NSString * _Nullable)contextKey completion:(QNAPIClientDictCompletionHandler)completion;
- (void)loadRemoteConfigList:(QNAPIClientArrayCompletionHandler)completion;
- (void)loadRemoteConfigListForContextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QNAPIClientArrayCompletionHandler)completion;
- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QNAPIClientEmptyCompletionHandler)completion;
- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QNAPIClientEmptyCompletionHandler)completion;
- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QNAPIClientEmptyCompletionHandler)completion;
- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QNAPIClientEmptyCompletionHandler)completion;
- (void)getPromotionalOfferForProduct:(QONProduct *)product
                             discount:(SKProductDiscount *)discount
                               userId:(NSString *)userId
                           identityId:(NSString *)identityId
                              receipt:(nullable NSString *)receipt
                           completion:(QNAPIClientDictCompletionHandler)completion API_AVAILABLE(ios(12.2), macos(10.14.4), watchos(6.2), tvos(12.2), visionos(1.0));

- (NSURLRequest *)handlePurchase:(QONStoreKit2PurchaseModel *)purchaseInfo
                         receipt:(nullable NSString *)receipt
                  requestTrigger:(QONRequestTrigger)requestTrigger
                      completion:(QNAPIClientDictCompletionHandler)completion;
- (void)sendCrashReport:(NSDictionary *)data completion:(QNAPIClientEmptyCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
