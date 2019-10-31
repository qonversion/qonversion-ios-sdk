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
static NSString * const kSDKVersion = @"0.6.0";

@interface Qonversion() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@property (nonatomic, readonly) NSMutableDictionary *transactions;
@property (nonatomic, readonly) NSMutableDictionary *productRequests;

@end

@implementation Qonversion

static NSString* apiKey;
static BOOL autoTrackPurchases;

// MARK: - Public

+ (void)launchWithKey:(nonnull NSString *)key autoTrackPurchases:(BOOL)autoTrack {
    [self launchWithKey:key autoTrackPurchases:autoTrack completion:^(NSString * _Nonnull uid) {
       // dummy
    }];
}

+ (void)launchWithKey:(nonnull NSString *)key completion:(nullable void (^)(NSString *uid))completion {
    [self launchWithKey:key autoTrackPurchases:YES completion:completion];
}

+ (void)launchWithKey:(nonnull NSString *)key autoTrackPurchases:(BOOL)autoTrack completion:(nullable void (^)(NSString *uid))completion {
    apiKey = key;
    autoTrackPurchases = autoTrack;
    if (autoTrack) {
        [SKPaymentQueue.defaultQueue addTransactionObserver:Qonversion.sharedInstance];
    }
    NSURLRequest *request = [self makePostRequestWithEndpoint:kInitEndpoint andBody:@{@"d": UserInfo.overallData}];
    [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
        if (!dict || ![dict respondsToSelector:@selector(valueForKey:)]) {
            return;
        }
        NSDictionary *dataDict = [dict valueForKey:@"data"];
        if (!dataDict || ![dataDict respondsToSelector:@selector(valueForKey:)]) {
            return;
        }
        NSString *uid = [dataDict valueForKey:@"client_uid"];
        if (uid && [uid isKindOfClass:NSString.class]) {
            Keeper.userID = uid;
            if (completion) {
                completion(uid);
            }
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
                                           @"receipt": receipt ?: @"",
                                           @"transactionIdentifier": transaction.transactionIdentifier ?: @"",
                                           @"originalTransactionIdentifier": transaction.originalTransaction.transactionIdentifier ?: @"",
                                           @"currency": currency,
                                           @"value": product.price.stringValue
                                           }.mutableCopy;

        if (@available(iOS 11.2, *)) {
            if (product.subscriptionPeriod != nil) {
                inappDict[@"subscriptionPeriodUnit"] = @(product.subscriptionPeriod.unit).stringValue;
                inappDict[@"subscriptionPeriodNumberOfUnits"] = @(product.subscriptionPeriod.numberOfUnits).stringValue;
            }

            if (product.introductoryPrice != nil) {
                SKProductDiscount *introductoryPrice = product.introductoryPrice;
                NSMutableDictionary *introductoryPriceDict = @{
                                                    @"value": introductoryPrice.price.stringValue,
                                                    @"numberOfPeriods": @(introductoryPrice.numberOfPeriods).stringValue,
                                                    @"subscriptionPeriodNumberOfUnits": @(introductoryPrice.subscriptionPeriod.numberOfUnits).stringValue,
                                                    @"subscriptionPeriodUnit": @(introductoryPrice.subscriptionPeriod.unit).stringValue,
                                                    @"paymentMode": @(introductoryPrice.paymentMode).stringValue
                                                }.mutableCopy;

                inappDict[@"introductoryPrice"] = introductoryPriceDict;
            }

        }

        NSDictionary *body = @{@"inapp": inappDict, @"d": UserInfo.overallData};
        
        NSURLRequest *request = [self makePostRequestWithEndpoint:kPurchaseEndpoint andBody:body];
        [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
            if (dict && [dict respondsToSelector:@selector(valueForKey:)]) {
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
    
    NSURL *docsURL = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if (docsURL) {
        NSDictionary *docsAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:docsURL.path error:nil];
        NSDate *date = docsAttributes.fileCreationDate;
        if (date) {
            NSString *unixTime = [NSString stringWithFormat:@"%ld", (long)round(date.timeIntervalSince1970)];
            [mutableBody setObject:unixTime forKey:@"install_date"];
        }
    }
    
    NSString *unixTime = [NSString stringWithFormat:@"%ld", (long)round(NSDate.new.timeIntervalSince1970)];
    [mutableBody setObject:unixTime forKey:@"launch_date"];
    
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];
    
    return request;
}

// MARK: - SKPaymentTransactionObserver

- (void)paymentQueue:(nonnull SKPaymentQueue *)queue updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
        if (transaction.transactionState != SKPaymentTransactionStatePurchased) {
            continue;
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
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
