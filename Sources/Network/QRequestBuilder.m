#import <Foundation/Foundation.h>
#import "QRequestBuilder.h"
#import "Keeper.h"

static NSString * const kAPIBase = @"https://api.qonversion.io";
static NSString * const kInitEndpoint = @"v1/user/init";

@interface QRequestBuilder ()

@property (nonatomic, strong) NSString *key;

@end

@implementation QRequestBuilder

- (instancetype)initWithKey:(NSString *)key {
    if (self = [super init]) {
        _key = key;
    }
    return self;
}

- (NSURLRequest *)makeInitRequestWithParameters:(NSDictionary *)parameters {
    
    NSString *endpoint = [kAPIBase stringByAppendingString:kInitEndpoint];
    NSURL *url = [[NSURL alloc] initWithString:endpoint];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL: url];
    
    request.HTTPMethod = @"POST";
    [request addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    NSMutableDictionary *mutableBody = parameters.mutableCopy;
 
    [mutableBody setObject:_key forKey:@"access_token"];
    NSString *clientUID = Keeper.userID;

    if (clientUID) {
        [mutableBody setObject:clientUID forKey:@"client_uid"];
    }

    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];
    return [request copy];
}

@end
