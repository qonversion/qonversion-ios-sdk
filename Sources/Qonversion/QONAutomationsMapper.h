//
//  QONAutomationsMapper.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONAutomationsScreen, QNUserActionPoint;

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsMapper : NSObject

- (nullable QONAutomationsScreen *)mapScreen:(NSDictionary *)dict;
- (nullable NSError *)mapError:(NSDictionary *)error;
- (NSArray<QNUserActionPoint *> *)mapUserActionPoints:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
