//
//  QNIdentityServiceInterface.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 22.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol QNIdentityServiceInterface <NSObject>

typedef void (^QNIdentityServiceCompletionHandler)(NSString *_Nullable result, NSError  *_Nullable error);

- (void)identify:(NSString *)userID anonUserID:(NSString *)anonUserID completion:(QNIdentityServiceCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
