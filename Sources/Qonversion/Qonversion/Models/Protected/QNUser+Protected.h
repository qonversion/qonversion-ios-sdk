//
//  QNUser+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 20.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNUser.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNUser (Protected)

- (instancetype)initWithID:(NSString *)identifier
        originalAppVersion:(NSString *)originalAppVersion;

@end

NS_ASSUME_NONNULL_END
