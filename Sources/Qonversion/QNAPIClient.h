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

- (void)properties:(NSDictionary *)properties completion:(QNAPIClientCompletionHandler)completion;
- (void)actionWithID:(NSString *)actionID completion:(QNAPIClientCompletionHandler)completion;

- (void)attributionRequest:(QNAttributionProvider)provider
                      data:(NSDictionary *)data
                completion:(QNAPIClientCompletionHandler)completion;
- (void)processStoredRequests;

@end

NS_ASSUME_NONNULL_END
