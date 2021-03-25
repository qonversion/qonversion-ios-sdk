//
//  QNUserInfoService.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNUserInfoServiceInterface.h"

@protocol QNLocalStorage, QNKeychainStorageInterface;

NS_ASSUME_NONNULL_BEGIN

@interface QNUserInfoService : NSObject <QNUserInfoServiceInterface>

@property (nonatomic, strong) id<QNKeychainStorageInterface> keychainStorage;
@property (nonatomic, strong) id<QNLocalStorage> localStorage;

@end

NS_ASSUME_NONNULL_END
