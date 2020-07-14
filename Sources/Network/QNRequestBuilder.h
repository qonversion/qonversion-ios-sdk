#import <Foundation/Foundation.h>

@interface QNRequestBuilder : NSObject

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters;

@end
