//
//  QNUser.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QNUser : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, nullable, readonly) NSString *originalAppVersion;

@end

NS_ASSUME_NONNULL_END
