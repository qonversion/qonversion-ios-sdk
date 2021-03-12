//
//  QONAutomationsScreenProcessor.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 09.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^QONAutomationsScreenProcessCompletionHandler)(NSString *_Nullable result, NSError  *_Nullable error);

@interface QONAutomationsScreenProcessor : NSObject

- (void)processScreen:(NSString *)htmlString completion:(QONAutomationsScreenProcessCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
