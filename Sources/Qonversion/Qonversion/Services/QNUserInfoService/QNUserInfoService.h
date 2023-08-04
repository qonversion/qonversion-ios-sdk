//
//  QNUserInfoService.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNUserInfoServiceInterface.h"

@class QNAPIClient;
@protocol QNLocalStorage, QNKeychainStorageInterface, QNUserInfoMapperInterface;

NS_ASSUME_NONNULL_BEGIN

@interface QNUserInfoService : NSObject <QNUserInfoServiceInterface>

@property (nonatomic, strong) id<QNLocalStorage> localStorage;
@property (nonatomic, strong) id<QNUserInfoMapperInterface> mapper;
@property (nonatomic, strong) QNAPIClient *apiClient;

@end

NS_ASSUME_NONNULL_END
