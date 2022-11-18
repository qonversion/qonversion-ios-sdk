//
//  QONOfferings.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONOffering;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.Offerings)
@interface QONOfferings : NSObject <NSCoding>

@property (nonatomic, copy, nonnull, readonly) NSArray<QONOffering *> *availableOfferings;

@property (nonatomic, strong, nullable, readonly) QONOffering *main;

- (nullable QONOffering *)offeringForIdentifier:(NSString *)offeringIdentifier
NS_SWIFT_NAME(offering(forIdentifier:));

@end

NS_ASSUME_NONNULL_END
