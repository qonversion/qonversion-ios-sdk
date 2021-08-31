//
//  QNDevice+Advertising.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 25.08.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNDevice.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNDevice (Advertising)

- (NSString *)obtainAdvertisingID;

@end

NS_ASSUME_NONNULL_END
