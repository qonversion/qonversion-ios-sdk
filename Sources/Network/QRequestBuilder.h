#import <Foundation/Foundation.h>

@interface QRequestBuilder : NSObject

- (NSURLRequest *)makeInitRequestWithParameters:(NSDictionary *)parameters;

+ (NSURLRequest *)makePostRequestWithEndpoint:(NSString *)endpoint andBody:(NSDictionary *)body;

@end
