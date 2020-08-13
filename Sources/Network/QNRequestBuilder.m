#import "QNRequestBuilder.h"

static NSString * const kAPIBase = @"https://api.qonversion.io/";
static NSString * const kInitEndpoint = @"v1/user/init";
static NSString * const kPurchaseEndpoint = @"v1/user/purchase";
static NSString * const kPropertiesEndpoint = @"v1/properties";


static NSString * const kAttributionEndpoint = @"attribution";

@implementation QNRequestBuilder

- (NSURLRequest *)makeInitRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWith:kInitEndpoint andBody:parameters];
}

- (NSURLRequest *)makePropertiesRequestWith:(NSDictionary *)parameters {
  return [self makePostRequestWith:kPropertiesEndpoint andBody:parameters];
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

  NSMutableURLRequest *request = [self baseRequestWithURL:url];
  NSMutableDictionary *mutableBody = body.mutableCopy ?: [NSMutableDictionary new];

  request.HTTPBody = [NSJSONSerialization dataWithJSONObject:mutableBody options:0 error:nil];
  
  return request.copy;
}

- (NSMutableURLRequest *)baseRequestWithURL:(NSURL *)url {
  NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL: url];
  
  request.HTTPMethod = @"POST";
  [request addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
  
  return request;
}

@end
