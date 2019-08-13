//
//  Qonversion.m
//  Qonversion
//
//  Created by Bogdan Novikov on 05/05/2019.
//

#import "Qonversion.h"
#import "Keeper.h"
#import "UserInfo.h"

static NSString * const kBaseURL = @"https://qonversion.io/api/";
static NSString * const kInitEndpoint = @"init";
static NSString * const kPurchaseEndpoint = @"purchase";
static NSString * const kSDKVersion = @"0.3.2";

@interface Qonversion() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@property (nonatomic, readonly) NSMutableDictionary *transactions;
@property (nonatomic, readonly) NSMutableDictionary *productRequests;

@end

@implementation Qonversion

static NSString* apiKey;
static BOOL autoTrackPurchases;

// MARK: - Public

+ (void)launchWithKey:(nonnull NSString *)key autoTrackPurchases:(BOOL)autoTrack {
    [self launchWithKey:key autoTrackPurchases:autoTrack completion:nil];
}

+ (void)launchWithKey:(nonnull NSString *)key autoTrackPurchases:(BOOL)autoTrack completion:(nullable void (^)(NSString *uid))completion {
    apiKey = key;
    autoTrackPurchases = autoTrack;
    if (autoTrack) {
        [SKPaymentQueue.defaultQueue addTransactionObserver:Qonversion.sharedInstance];
    }
    NSURLRequest *request = [self makePostRequestWithEndpoint:kInitEndpoint andBody:@{@"d": UserInfo.overallData}];
    [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
        if (!dict || ![dict isKindOfClass:NSDictionary.class]) {
            return;
        }
        NSDictionary *dataDict = [dict valueForKey:@"data"];
        if (!dataDict || ![dataDict isKindOfClass:NSDictionary.class]) {
            return;
        }
        NSString *uid = [dataDict valueForKey:@"client_uid"];
        if (uid && [uid isKindOfClass:NSString.class]) {
            Keeper.userID = uid;
            completion(uid);
        }
    }];
}

+ (void)trackPurchase:(nonnull SKProduct *)product transaction:(nonnull SKPaymentTransaction *)transaction {
    if (autoTrackPurchases) {
        NSLog(@"'autoTrackPurchases' enabled in `launchWithKey:autoTrackPurchases`, so manual 'trackPurchase:transaction:' just won't send duplicate data");
        return;
    }
    [self serviceLogPurchase:product transaction:transaction];
}

// MARK: - Private

- (instancetype)init {
    self = super.init;
    if (self) {
        _transactions = [NSMutableDictionary dictionaryWithCapacity:1];
        _productRequests = [NSMutableDictionary dictionaryWithCapacity:1];
    }
    return self;
}

+ (instancetype)sharedInstance {
    static id shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = self.new;
    });
    return shared;
}

+ (void)serviceLogPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURL *receiptURL = UserInfo.bundle.appStoreReceiptURL;
        if (!receiptURL) {
            return;
        }
        NSString *currency;
        if (@available(iOS 10.0, *)) {
            currency = product.priceLocale.currencyCode;
        } else {
            NSNumberFormatter *formatter = NSNumberFormatter.new;
            [formatter setNumberStyle:NSNumberFormatterCurrencyISOCodeStyle];
            [formatter setLocale:product.priceLocale];
            currency = [formatter stringFromNumber:product.price];
        }
        NSString *receipt = [[NSData dataWithContentsOfURL:receiptURL] base64EncodedStringWithOptions:0];
        
        NSMutableDictionary *inappDict = @{@"product": product.productIdentifier,
                                           @"receipt": receipt,
                                           @"transactionIdentifier": transaction.transactionIdentifier ?: @"",
                                           @"originalTransactionIdentifier": transaction.originalTransaction.transactionIdentifier ?: @"",
                                           @"currency": currency,
                                           @"value": product.price.stringValue
                                           }.mutableCopy;
        
        NSDictionary *body = @{@"inapp": inappDict, @"d": UserInfo.overallData};
        
        NSURLRequest *request = [self makePostRequestWithEndpoint:kPurchaseEndpoint andBody:body];
        [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
            if (dict) {
                NSLog(@"Qonversion Purchase Log Response:\n%@", dict);
            }
        }];
    });
}

+ (void)dataTaskWithRequest:(NSURLRequest *)request completion:(void (^)(NSDictionary *dict))completion {
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
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

+ (NSURLRequest *)makePostRequestWithEndpoint:(NSString *)endpoint andBody:(NSDictionary *)body {
    NSURL *url = [NSURL.alloc initWithString:[kBaseURL stringByAppendingString:endpoint]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest.alloc initWithURL:url];
    request.HTTPMethod = @"POST";
    [request addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    
    NSMutableDictionary *mutableBody = body.mutableCopy;
    
    [mutableBody setObject:apiKey forKey:@"access_token"];
    [mutableBody setObject:kSDKVersion forKey:@"v"];
    if (Keeper.userID && Keeper.userID.length > 2) {
        [mutableBody setObject:Keeper.userID forKey:@"client_uid"];
    }
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];
    
    return request;
}

// MARK: - SKPaymentTransactionObserver

- (void)paymentQueue:(nonnull SKPaymentQueue *)queue updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
        if (transaction.transactionState != SKPaymentTransactionStatePurchased) {
            continue;
        }
        [self.transactions setObject:transaction forKey:transaction.payment.productIdentifier];
        
        SKProductsRequest *request = [SKProductsRequest.alloc initWithProductIdentifiers:[NSSet setWithObject:transaction.payment.productIdentifier]];
        [self.productRequests setObject:request forKey:transaction.payment.productIdentifier];
        request.delegate = self;
        [request start];
    }
}

// MARK: - SKProductsRequestDelegate

- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response {
    SKProduct *product = response.products.firstObject;
    if (!product) {
        return;
    }
    SKPaymentTransaction *transaction = [self.transactions objectForKey:product.productIdentifier];
    if (!transaction) {
        return;
    }
    [Qonversion serviceLogPurchase:product transaction:transaction];
    [self.transactions removeObjectForKey:product.productIdentifier];
    [self.productRequests removeObjectForKey:product.productIdentifier];
}

@end
