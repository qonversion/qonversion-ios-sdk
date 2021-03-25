#import <Foundation/Foundation.h>

@interface QNRequestBuilder : NSObject

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeAttributionRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makePurchaseRequestWith:(NSDictionary *)parameters;
- (NSURLRequest *)makeUserActionPointsRequestWith:(NSString *)parameter apiKey:(NSString *)apiKey;
- (NSURLRequest *)makeScreensRequestWith:(NSString *)parameters apiKey:(NSString *)apiKey;
- (NSURLRequest *)makeCreateIdentityRequestWith:(NSDictionary *)parameters apiKey:(NSString *)apiKey;
- (NSURLRequest *)makeScreenShownRequestWith:(NSString *)parameter body:(NSDictionary *)body apiKey:(NSString *)apiKey;
- (NSURLRequest *)makeIntroTrialEligibilityRequestWithData:(NSDictionary *)parameters;

@end
