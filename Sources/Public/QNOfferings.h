//
//  QNOfferings.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNOffering;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.Offerings)
@interface QNOfferings : NSObject <NSCoding>

@property (nonatomic, copy, nonnull, readonly) NSArray<QNOffering *> *availableOfferings;

@property (nonatomic, strong, nullable, readonly) QNOffering *main;

- (nullable QNOffering *)offeringForIdentifier:(NSString *)offeringIdentifier;

@end

NS_ASSUME_NONNULL_END
