//
//  NSError+Sugare.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSError (Sugare)

- (BOOL)shouldFireFallback;

@end

NS_ASSUME_NONNULL_END
