//
//  IPInfo.h
//  Qonversion
//
//  Created by Bogdan Novikov on 24/05/2019.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IPInfo : NSObject

- (void)fetchIP:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
