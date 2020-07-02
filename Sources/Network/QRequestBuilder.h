#import <Foundation/Foundation.h>

@interface QRequestBuilder : NSObject

- (instancetype)initWithKey:(NSString *)key;

@property (nonatomic, copy, readonly) NSString *apiKey;

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeCheckRequest;
- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters;

@end
