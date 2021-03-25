//
//  QNKeychainStorageInterface.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QNKeychainStorageInterface <NSObject>

- (NSString *_Nullable)obtainUserID:(NSUInteger)maxAttemptsCount;
- (void)resetUserID;

@end
