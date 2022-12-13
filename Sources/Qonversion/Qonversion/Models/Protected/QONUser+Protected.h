//
//  QONUser+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 20.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONUser.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONUser (Protected)

- (instancetype)initWithID:(NSString *)qonversionId
        originalAppVersion:(NSString *)originalAppVersion
                identityId:(NSString *_Nullable)identityId;

@end

NS_ASSUME_NONNULL_END
