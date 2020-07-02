#import <Foundation/Foundation.h>
#import "QRequestBuilder.h"
#import "Keeper.h"
#import "QUtils.h"

static NSString * const kAPIBase = @"https://api.qonversion.io/";
static NSString * const kInitEndpoint = @"v1/user/init";
static NSString * const kPropertiesEndpoint = @"v1/properties";
static NSString * const kCheckEndpoint = @"check";
static NSString * const kAttributionEndpoint = @"attribution";
static NSString * const kPurchaseEndpoint = @"purchase";

@interface QRequestBuilder ()

@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, strong) NSString *userID;

@end

@implementation QRequestBuilder

- (instancetype)initWithKey:(NSString *)key {
    if (self = [super init]) {
        _apiKey = key;
    }
    return self;
}

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters {
    return [self makePostRequestWith:kInitEndpoint andBody:parameters];
}

- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters {
    return [self makePostRequestWith:kPropertiesEndpoint andBody:parameters];
}

- (NSURLRequest *)makeCheckRequest {
    return [self makePostRequestWith:kCheckEndpoint andBody:@{}];
}

- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters {
    return [self makePostRequestWith:kAttributionEndpoint andBody:parameters];
}

- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters {
    return [self makePostRequestWith:kPurchaseEndpoint andBody:parameters];
}

// MARK: Private

- (NSURLRequest *)makePostRequestWith:(NSString *)endpoint andBody:(NSDictionary *)body {
    
    NSString *urlString = [kAPIBase stringByAppendingString:endpoint];
    NSURL *url = [NSURL.alloc initWithString:urlString];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL: url];
    
    request.HTTPMethod = @"POST";
    [request addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    
    NSMutableDictionary *mutableBody = body.mutableCopy ?: [NSMutableDictionary new];
    
    [mutableBody setObject:_apiKey forKey:@"access_token"];
    if ([QUtils isEmptyString:_userID]) {
        NSString *clientUID = Keeper.userID;
        _userID = clientUID;
    }
    
    if (_userID) {
        [mutableBody setObject:_userID forKey:@"q_uid"];
        [mutableBody setObject:_userID forKey:@"client_uid"];
    }

    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];
    
    return request.copy;
}

@end
