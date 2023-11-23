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

/**
 Returns Qonversion Offering for specific ID
 @param offeringIdentifier - id of the offering you want to get
 @return Qonversion Offering or nil if no offering found for the passed identifier
 */
- (nullable QONOffering *)offeringForIdentifier:(nonnull NSString *)offeringIdentifier
NS_SWIFT_NAME(offering(for:));

@end

NS_ASSUME_NONNULL_END
