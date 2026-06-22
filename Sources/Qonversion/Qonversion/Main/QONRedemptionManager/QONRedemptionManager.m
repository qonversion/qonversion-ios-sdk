//
//  QONRedemptionManager.m
//  Qonversion
//

#import "QONRedemptionManager.h"
#import "QNAPIConstants.h"
#import "QNAPIClient.h"
#import "QNProductCenterManager.h"
#import "QNUserInfoServiceInterface.h"
#import "QNUtils.h"
#import "QNDevice.h"
#import "QNInternalConstants.h"

@implementation QONRedemptionManager

- (instancetype)init {
  self = [super init];
  if (self) {
    _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    _baseURL = kAPIBase;
  }
  return self;
}

// MARK: - Public

+ (nullable NSString *)tokenFromURL:(NSURL *)url {
  if (!url) {
    return nil;
  }

  // Universal Link form: https://<host>/r/{project_uid}/{token}
  // Also accept custom-scheme host-app→SDK forwarding e.g. qonversion://r/{project_uid}/{token}
  NSArray<NSString *> *segments = [url.path componentsSeparatedByString:@"/"];
  NSMutableArray<NSString *> *trimmed = [NSMutableArray new];
  for (NSString *seg in segments) {
    if (seg.length > 0) {
      [trimmed addObject:seg];
    }
  }

  // Expect: ["r", project_uid, token]
  NSInteger rIndex = [trimmed indexOfObject:@"r"];
  if (rIndex == NSNotFound) {
    return nil;
  }

  // token is two segments after "r"
  NSInteger tokenIndex = rIndex + 2;
  if (tokenIndex >= (NSInteger)trimmed.count) {
    return nil;
  }

  NSString *token = trimmed[tokenIndex];
  if (token.length == 0) {
    return nil;
  }

  // Strip any query string that snuck through
  NSRange q = [token rangeOfString:@"?"];
  if (q.location != NSNotFound) {
    token = [token substringToIndex:q.location];
  }

  return token.length > 0 ? token : nil;
}

- (void)handleRedemptionLink:(NSURL *)url completion:(QONRedemptionCompletionHandler)completion {
  // Spec rule RT2-W3 (Web 2 App M1): Universal Links are the ONLY supported
  // transport for email-borne redemption links. The custom `qonversion://`
  // scheme is left as a *parser-level* concession for in-process
  // host-app→SDK forwarding (`+tokenFromURL:`), but this public entry point
  // — documented as the email→app handoff — must reject any non-https URL
  // before issuing a network request. Any installed app can register the
  // custom scheme in its CFBundleURLTypes and hijack the redemption token
  // otherwise.
  NSString *scheme = [url.scheme lowercaseString];
  if (![scheme isEqualToString:@"https"]) {
    [self deliver:QONRedemptionResultInvalidToken completion:completion];
    return;
  }

  NSString *token = [QONRedemptionManager tokenFromURL:url];
  if (token.length == 0) {
    [self deliver:QONRedemptionResultInvalidToken completion:completion];
    return;
  }

  NSString *anonUserID = [self.userInfoService obtainUserID];
  NSMutableDictionary *body = [NSMutableDictionary new];
  body[@"token"] = token;
  if (anonUserID.length > 0) {
    body[@"anon_user_id"] = anonUserID;
  }
  // RestoreBehavior=Transfer is the default per plan §"Collision behavior".
  body[@"restore_behavior"] = @"transfer";

  __weak QONRedemptionManager *weakSelf = self;
  [self postJSON:body
        endpoint:kWebRedeemEndpoint
      completion:^(NSInteger statusCode, NSDictionary * _Nullable response, NSError * _Nullable transportError) {
    QONRedemptionManager *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    if (transportError != nil) {
      [strongSelf deliver:QONRedemptionResultNetworkError completion:completion];
      return;
    }

    if (statusCode >= 200 && statusCode < 300) {
      // Trigger anon→app identity merge so entitlements roll up under the
      // newly-issued app-side user. Per RT5-N2: identify must trigger a
      // launch/permissions fetch — that is the existing contract of
      // QNProductCenterManager.identify:, see Qonversion+Redemption tests.
      NSString *appUserID = response[@"user_id"];
      // productCenterManager is a weak ref; if it has been released we must NOT
      // trap the success delivery inside its identify: completion (which would
      // then never fire, hanging the caller). Only route through identify when
      // the manager is alive AND we have a user_id; otherwise deliver success
      // directly — redemption already succeeded server-side (HTTP 2xx).
      QNProductCenterManager *productCenter = strongSelf.productCenterManager;
      if (productCenter != nil && [appUserID isKindOfClass:[NSString class]] && appUserID.length > 0) {
        [productCenter identify:appUserID completion:^(QONUser * _Nullable user, NSError * _Nullable error) {
          // Identify result is best-effort; success of redemption is already
          // determined by the HTTP 2xx. We surface .success either way and
          // let the host app fetch entitlements on next cycle.
          [strongSelf deliver:QONRedemptionResultSuccess completion:completion];
        }];
        return;
      }
      [strongSelf deliver:QONRedemptionResultSuccess completion:completion];
      return;
    }

    if (statusCode == 404) {
      [strongSelf deliver:QONRedemptionResultInvalidToken completion:completion];
      return;
    }

    if (statusCode == 410) {
      [strongSelf deliver:QONRedemptionResultTokenExpired completion:completion];
      return;
    }

    if (statusCode == 409) {
      // RT4-W2 recovery branch — confirm via /v4/web/redeem/status whether
      // the token is genuinely already-consumed, then surface that to host.
      [strongSelf checkRedemptionStatusForToken:token completion:completion];
      return;
    }

    // 4xx (other) or 5xx — treat as network/transient.
    [strongSelf deliver:QONRedemptionResultNetworkError completion:completion];
  }];
}

- (void)reissueWithEmail:(NSString *)email completion:(QONReissueCompletionHandler)completion {
  NSDictionary *body = email.length > 0 ? @{@"email": email} : @{};

  [self postJSON:body
        endpoint:kWebRedeemReissueEndpoint
      completion:^(NSInteger statusCode, NSDictionary * _Nullable response, NSError * _Nullable transportError) {
    BOOL success = (transportError == nil) && statusCode >= 200 && statusCode < 300;
    if (completion) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(success, statusCode, transportError);
      });
    }
  }];
}

// MARK: - Private

- (void)checkRedemptionStatusForToken:(NSString *)token completion:(QONRedemptionCompletionHandler)completion {
  __weak QONRedemptionManager *weakSelf = self;
  [self postJSON:@{@"token": token}
        endpoint:kWebRedeemStatusEndpoint
      completion:^(NSInteger statusCode, NSDictionary * _Nullable response, NSError * _Nullable transportError) {
    QONRedemptionManager *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    if (transportError != nil) {
      [strongSelf deliver:QONRedemptionResultNetworkError completion:completion];
      return;
    }

    // If status check itself failed, treat as networkError so host shows
    // a retry rather than the more specific "already used" UI.
    if (statusCode < 200 || statusCode >= 300) {
      [strongSelf deliver:QONRedemptionResultNetworkError completion:completion];
      return;
    }

    id consumed = response[@"consumed"];
    BOOL isConsumed = [consumed respondsToSelector:@selector(boolValue)] && [consumed boolValue];
    [strongSelf deliver:(isConsumed ? QONRedemptionResultAlreadyConsumed : QONRedemptionResultInvalidToken)
             completion:completion];
  }];
}

- (void)deliver:(QONRedemptionResult)result completion:(QONRedemptionCompletionHandler)completion {
  if (!completion) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    completion(result);
  });
}

- (void)postJSON:(NSDictionary *)body
        endpoint:(NSString *)endpoint
      completion:(void (^)(NSInteger statusCode, NSDictionary * _Nullable response, NSError * _Nullable transportError))completion {
  NSString *urlString = [self.baseURL stringByAppendingString:endpoint];
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) {
    if (completion) {
      completion(0, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil]);
    }
    return;
  }

  NSError *jsonError = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:(body ?: @{}) options:0 error:&jsonError];
  if (jsonError) {
    if (completion) {
      completion(0, nil, jsonError);
    }
    return;
  }

  NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
  request.HTTPMethod = @"POST";
  request.HTTPBody = data;
  [request addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

  // Auth + platform headers — re-use the shared API client's project key.
  NSString *apiKey = [QNAPIClient shared].apiKey;
  if (apiKey.length > 0) {
    BOOL debug = [QNAPIClient shared].debug;
    NSString *bearer = debug ? [NSString stringWithFormat:@"Bearer test_%@", apiKey]
                             : [NSString stringWithFormat:@"Bearer %@", apiKey];
    [request addValue:bearer forHTTPHeaderField:@"Authorization"];
  }
  [request addValue:[QNDevice current].osName forHTTPHeaderField:@"Platform"];
  [request addValue:[QNDevice current].osVersion forHTTPHeaderField:@"Platform-Version"];
  NSString *source = [[NSUserDefaults standardUserDefaults] stringForKey:keyQSource] ?: @"iOS";
  [request addValue:source forHTTPHeaderField:@"Source"];

  NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                               completionHandler:^(NSData * _Nullable responseData,
                                                                   NSURLResponse * _Nullable response,
                                                                   NSError * _Nullable error) {
    if (error) {
      if (completion) {
        completion(0, nil, error);
      }
      return;
    }

    NSInteger statusCode = 0;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
      statusCode = ((NSHTTPURLResponse *)response).statusCode;
    }

    NSDictionary *dict = nil;
    if (responseData.length > 0) {
      id parsed = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
      if ([parsed isKindOfClass:[NSDictionary class]]) {
        dict = parsed;
      }
    }

    if (completion) {
      completion(statusCode, dict, nil);
    }
  }];
  [task resume];
}

@end
