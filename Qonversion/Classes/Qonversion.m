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

@interface Qonversion() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@property (nonatomic, readonly) NSMutableDictionary *transactions;
@property (nonatomic, readonly) NSMutableDictionary *productRequests;

@end

@implementation Qonversion

static NSString* apiKey;
static BOOL autoTrackPurchases;

// MARK: - Public

+ (void)launchWithKey:(NSString *)key autoTrackPurchases:(BOOL)autoTrack completion:(void (^)(NSString *uid))completion {
    apiKey = key;
    autoTrackPurchases = autoTrack;
    if (autoTrack) {
        [SKPaymentQueue.defaultQueue addTransactionObserver:Qonversion.sharedInstance];
    }
    NSURLRequest *request = [self makePostRequestWithEndpoint:kInitEndpoint andBody:@{@"d": UserInfo.overallData}];
    [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
        NSString *uid = [[dict valueForKey:@"data"] valueForKey:@"client_uid"];
        if (!uid) {
            return;
        }
        Keeper.userID = uid;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(uid);
        });
    }];
}

+ (void)trackPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
    if (autoTrackPurchases) {
        NSLog(@"'autoTrackPurchases' enabled, manual 'trackPurchase:transaction:' disabled");
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
                                           @"transactionIdentifier": transaction.transactionIdentifier,
                                           @"currency": currency,
                                           @"value": product.price.stringValue
                                           }.mutableCopy;
        
        if (transaction.originalTransaction.transactionIdentifier) {
            inappDict[@"originalTransactionIdentifier"] = transaction.originalTransaction.transactionIdentifier;
        }
        NSDictionary *body = @{@"inapp": inappDict, @"d": UserInfo.overallData};
        
        NSURLRequest *request = [self makePostRequestWithEndpoint:kPurchaseEndpoint andBody:body];
        [self dataTaskWithRequest:request completion:^(NSDictionary *dict) { }];
    });
}

+ (void)dataTaskWithRequest:(NSURLRequest *)request completion:(void (^)(NSDictionary *dict))completion {
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (!data) {
            return;
        }
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!dict) {
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
    [mutableBody setObject:@"0.2.5" forKey:@"v"];
    if (Keeper.userID) {
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
    if (!response.products.firstObject) {
        return;
    }
    SKProduct *product = response.products.firstObject;
    SKPaymentTransaction *transaction = [self.transactions objectForKey:product.productIdentifier];
    
    [Qonversion serviceLogPurchase:product transaction:transaction];
    [self.transactions removeObjectForKey:product.productIdentifier];
    [self.productRequests removeObjectForKey:product.productIdentifier];
}

@end
