//
//  QONRequest.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 13.09.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#ifndef QNRequest_h
#define QNRequest_h

#import <Foundation/Foundation.h>
#import "QONRateLimiter.h"

@interface QONRequest : NSObject

@property (nonatomic, assign, readonly) NSTimeInterval timestamp;
@property (nonatomic, assign, readonly) NSUInteger hashValue;

- (instancetype)initWithTimestamp:(NSTimeInterval)timestamp andHash:(NSUInteger)hashValue;

@end

#endif /* QNRequest_h */
