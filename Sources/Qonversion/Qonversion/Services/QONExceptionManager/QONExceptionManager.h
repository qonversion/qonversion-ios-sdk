//
// Created by Kamo Spertsyan on 31.05.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONExceptionManagerInterface.h"

@class QNAPIClient;

NS_ASSUME_NONNULL_BEGIN

@interface QONExceptionManager : NSObject <QONExceptionManagerInterface>

@property (nonatomic, strong) QNAPIClient *apiClient;

@end

NS_ASSUME_NONNULL_END
