//
// Created by Kamo Spertsyan on 31.05.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNAPIClient;

NS_ASSUME_NONNULL_BEGIN

@interface QONExceptionManager : NSObject

@property (nonatomic, strong) QNAPIClient *apiClient;

+ (instancetype)shared;

- (BOOL)isQonversionException:(NSException * _Nonnull)exception isSpm:(BOOL *)isSpm;

- (void)storeException:(NSException * _Nonnull)exception isSpm:(BOOL)isSpm;

@end

NS_ASSUME_NONNULL_END
