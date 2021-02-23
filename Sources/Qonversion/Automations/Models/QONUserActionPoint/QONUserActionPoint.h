//
//  QONUserActionPoint.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 28.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QONUserActionPoint : NSObject

@property (nonatomic, copy, readonly) NSString *screenId;
@property (nonatomic, strong, readonly) NSDate *createDate;

- (instancetype)initWithScreenId:(NSString *)screenId createDate:(NSDate *)createDate;

@end

NS_ASSUME_NONNULL_END
