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

NSString * const QONRedemptionErrorDomain = @"com.qonversion.redemption";

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

  // Canonical structure is exactly ["r", project_uid, token]. The "r" prefix
  // MUST be the FIRST path segment — searching for "r" anywhere (the previous
  // behaviour) let a nested "r" segment such as /foo/r/proj/token be parsed as
  // a redemption link (path type-confusion). Pin it to index 0 for Android
  // parity. (#8)
  if (trimmed.count == 0 || ![trimmed.firstObject isEqualToString:@"r"]) {
    return nil;
  }

  // token is two segments after the leading "r"
  NSInteger tokenIndex = 2;
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

  // #8 — host pinning (defense-in-depth, Android parity). The email-borne
  // redemption link is always served from `screens.qonversion.io`. Reject any
  // other host BEFORE touching the network so a look-alike / attacker host can
  // never coax the SDK into POSTing (and thereby burning) a single-use token.
  // DNS hosts are case-insensitive, so compare case-insensitively.
  NSString *host = [url.host lowercaseString];
  if (![host isEqualToString:kRedemptionLinkHost]) {
    [self deliver:QONRedemptionResultInvalidToken completion:completion];
    return;
  }

  NSString *token = [QONRedemptionManager tokenFromURL:url];
  if (token.length == 0) {
    [self deliver:QONRedemptionResultInvalidToken completion:completion];
    return;
  }

  NSString *appUID = [self.userInfoService obtainUserID];
  if (appUID.length == 0) {
    // Web2App M1.5 canonical contract: app_uid is required so the backend
    // can attach the granted entitlement to a user under grant-first. value
    // is unchanged (obtainUserID); only the field name changed from the
    // legacy "anon_user_id". `obtainUserID` is expected to lazily
    // generate+persist one, so an empty value here is a transient SDK
    // precondition failure (e.g. the user info service has not finished
    // bootstrapping). We must NOT silently fire a redeem that omits the
    // field — that would consume a single-use token on the backend with no
    // way to attach the resulting entitlement to a user. Surface a retryable
    // outcome and issue no network request.
    [self deliver:QONRedemptionResultRetryable completion:completion];
    return;
  }

  NSMutableDictionary *body = [NSMutableDictionary new];
  body[@"token"] = token;
  // Canonical contract field name: "app_uid" (renamed from "anon_user_id";
  // api-gateway and purchaseman read "app_uid"). value = obtainUserID.
  body[@"app_uid"] = appUID;
  // RestoreBehavior=Transfer is the default per plan §"Collision behavior".
  body[@"restore_behavior"] = @"transfer";

  // overview r6: one Idempotency-Key (UUIDv4) per *logical* redeem call — not
  // per HTTP attempt. Generated here so every HTTP request belonging to this
  // logical redeem (the redeem POST plus any 409→/status recovery call or
  // transport-level retry) carries the same key and the backend can dedup
  // double-taps / retries.
  NSString *idempotencyKey = [NSUUID UUID].UUIDString;

  __weak QONRedemptionManager *weakSelf = self;
  [self postJSON:body
        endpoint:kWebRedeemEndpoint
  idempotencyKey:idempotencyKey
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
      // Web2App M1.5 canonical contract: response is { redeemed, app_uid } —
      // there is NO user_id. Under grant-first the entitlement is ALREADY
      // granted server-side for app_uid, so the SDK must NOT call
      // identify(userId)/merge. Instead it triggers a server-state refresh
      // for the current user (launch / actualize permissions) so the host
      // app's next checkEntitlements sees the granted product.
      //
      // productCenterManager is a weak ref; if it has been released we simply
      // deliver success — redemption already succeeded server-side (HTTP 2xx)
      // and the host app will pick up the entitlement on its next cycle.
      QNProductCenterManager *productCenter = strongSelf.productCenterManager;
      [productCenter launchWithTrigger:QONRequestTriggerActualizePermissions completion:nil];
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
      // Same logical redeem → reuse the same Idempotency-Key.
      [strongSelf checkRedemptionStatusForToken:token
                                 idempotencyKey:idempotencyKey
                                     completion:completion];
      return;
    }

    // 429 (rate limit) and 5xx (server error), plus any other non-mapped 4xx
    // (401/403/etc.): the server was reachable and responded, so this is NOT
    // a "no network" condition. Surface `.retryable` so the host shows a
    // back-off/retry affordance rather than a misleading offline error.
    [strongSelf deliver:QONRedemptionResultRetryable completion:completion];
  }];
}

- (void)reissueWithEmail:(NSString *)email completion:(QONReissueCompletionHandler)completion {
  // #10 — fail fast on an empty / whitespace-only email. Previously an empty
  // email POSTed an empty body `{}`, burning a request the backend can only
  // reject. Gate it at the public boundary and surface a validation error
  // WITHOUT issuing a network request.
  NSString *trimmedEmail = [email stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmedEmail.length == 0) {
    if (completion) {
      NSError *error = [NSError errorWithDomain:QONRedemptionErrorDomain
                                           code:QONRedemptionErrorCodeEmptyEmail
                                       userInfo:@{NSLocalizedDescriptionKey: @"A non-empty email is required to reissue a redemption link."}];
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(NO, 0, error);
      });
    }
    return;
  }

  // Reissue is its own logical operation → its own Idempotency-Key.
  [self postJSON:@{@"email": trimmedEmail}
        endpoint:kWebRedeemReissueEndpoint
  idempotencyKey:[NSUUID UUID].UUIDString
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

- (void)checkRedemptionStatusForToken:(NSString *)token
                       idempotencyKey:(NSString *)idempotencyKey
                           completion:(QONRedemptionCompletionHandler)completion {
  __weak QONRedemptionManager *weakSelf = self;
  [self postJSON:@{@"token": token}
        endpoint:kWebRedeemStatusEndpoint
  idempotencyKey:idempotencyKey
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

    // #5 — Map the status payload, honouring BOTH `consumed` and `expired`.
    // "consumed" is the stronger statement (the token was actually used), so it
    // wins when both are set; otherwise an `expired` token surfaces as
    // TokenExpired (Android parity) so the host can offer the reissue flow,
    // rather than the misleading InvalidToken. Only a token that is neither
    // consumed nor expired is genuinely InvalidToken.
    id consumed = response[@"consumed"];
    id expired = response[@"expired"];
    BOOL isConsumed = [consumed respondsToSelector:@selector(boolValue)] && [consumed boolValue];
    BOOL isExpired = [expired respondsToSelector:@selector(boolValue)] && [expired boolValue];

    QONRedemptionResult result;
    if (isConsumed) {
      result = QONRedemptionResultAlreadyConsumed;
    } else if (isExpired) {
      result = QONRedemptionResultTokenExpired;
    } else {
      result = QONRedemptionResultInvalidToken;
    }
    [strongSelf deliver:result completion:completion];
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
  idempotencyKey:(nullable NSString *)idempotencyKey
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

  // overview r6: mandatory dedup key for the logical redeem/reissue call.
  if (idempotencyKey.length > 0) {
    [request addValue:idempotencyKey forHTTPHeaderField:@"Idempotency-Key"];
  }

  // Auth + platform headers — re-use the shared API client's project key.
  //
  // #11 (refactor debt): this Bearer construction is inlined rather than
  // delegated to -[QNRequestBuilder addBearerToRequest:] ON PURPOSE. That
  // helper emits a plain `Bearer <apiKey>` and does NOT prepend the debug
  // `test_` prefix, whereas the Web2App redeem contract requires
  // `Bearer test_<apiKey>` in debug mode (verified, matches Android). Folding
  // this into the existing helper would silently drop the `test_` prefix and
  // regress auth. TODO(DEV-847 follow-up): hoist a single debug-aware Bearer
  // builder shared by QNRequestBuilder and QONRedemptionManager, then route
  // both through it.
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
