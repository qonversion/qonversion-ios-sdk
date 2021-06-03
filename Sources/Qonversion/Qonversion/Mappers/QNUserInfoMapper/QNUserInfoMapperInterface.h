//
//  QNUserInfoMapperInterface.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 19.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNUser;

NS_ASSUME_NONNULL_BEGIN

@protocol QNUserInfoMapperInterface <NSObject>

- (QNUser *)mapUserInfo:(NSDictionary *)data;

@end

NS_ASSUME_NONNULL_END
