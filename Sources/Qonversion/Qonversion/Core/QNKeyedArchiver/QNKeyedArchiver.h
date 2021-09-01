//
//  QNKeyedArchiver.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 31.08.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QNKeyedArchiver : NSObject

+ (nullable NSData *)archivedDataWithObject:(nonnull id)object;
+ (nullable id)unarchiveObjectWithData:(nonnull NSData *)data;

@end

NS_ASSUME_NONNULL_END
