//
//  QNErrorsMapper.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 22.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QNErrorsMapper : NSObject

- (NSError *)errorFromRequestResult:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
