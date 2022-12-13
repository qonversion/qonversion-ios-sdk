//
//  QNIdentityService.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 22.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNIdentityService.h"
#import "QNAPIClient.h"
#import "QONErrors.h"

@implementation QNIdentityService

- (void)identify:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNIdentityServiceCompletionHandler)completion {
  [self.apiClient createIdentityForUserID:userID anonUserID:anonUserID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    NSString *identityID = dict[@"data"][@"anon_id"];
    if (identityID.length > 0) {
      completion(identityID, nil);
    } else {
      NSError *resultError = error ?: [QONErrors errorWithQONErrorCode:QONErrorInternalError];
      completion(nil, resultError);
    }
  }];
}

@end
