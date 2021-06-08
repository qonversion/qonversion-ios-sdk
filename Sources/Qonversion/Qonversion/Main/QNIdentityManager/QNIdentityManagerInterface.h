//
//  QNIdentityManagerInterface.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol QNIdentityManagerInterface <NSObject>

typedef void (^QNIdentityCompletionHandler)(NSString *_Nullable result, NSError  *_Nullable error);

- (void)identify:(NSString *)userID completion:(QNIdentityCompletionHandler)completion;
- (BOOL)logoutIfNeeded;

@end

NS_ASSUME_NONNULL_END
