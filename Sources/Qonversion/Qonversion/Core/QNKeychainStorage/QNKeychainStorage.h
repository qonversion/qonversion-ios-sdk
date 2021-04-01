//
//  QNKeychainStorage.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNKeychainStorageInterface.h"

@class QNKeychain;

NS_ASSUME_NONNULL_BEGIN

@interface QNKeychainStorage : NSObject <QNKeychainStorageInterface>

@property (nonatomic, strong) QNKeychain *keychain;

@end

NS_ASSUME_NONNULL_END
