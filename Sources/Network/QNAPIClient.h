#import "Qonversion.h"
#import <Foundation/Foundation.h>

@class SKProduct, SKPaymentTransaction;

typedef void (^QNAPIClientCompletionHandler)(NSDictionary * _Nullable dict, NSError * _Nullable error);

NS_ASSUME_NONNULL_BEGIN

@interface QNAPIClient : NSObject

+ (instancetype)shared;

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) NSString *apiKey;

- (void)launchRequest:(QNAPIClientCompletionHandler)completion;

- (void)purchaseRequestWith:(SKProduct *)product
                transaction:(SKPaymentTransaction *)transaction
                 completion:(QNAPIClientCompletionHandler)completion;

- (void)properties:(NSDictionary *)properties completion:(QNAPIClientCompletionHandler)completion;
- (void)attributionRequest:(NSDictionary *)properties completion:(QNAPIClientCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END