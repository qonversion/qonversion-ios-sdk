//
//  QNIdentityServiceInterface.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 22.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

@protocol QNIdentityServiceInterface <NSObject>

typedef void (^QNIdentityServiceCompletionHandler)(NSString *_Nullable result, NSError  *_Nullable error);

- (void)checkIdentityForUserID:(NSString *)userID completion:(QNIdentityServiceCompletionHandler)completion;
- (void)identify:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNIdentityServiceCompletionHandler)completion;

@end
