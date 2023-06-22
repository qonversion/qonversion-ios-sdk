//
//  QONOffering.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONProduct;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONOfferingTag) {
  QONOfferingTagUnknown = -1,
  QONOfferingTagNone = 0,
  /**
   Provides access to content on a recurring basis with a free introductory offer
   */
  QONOfferingTagMain = 1
} NS_SWIFT_NAME(Qonversion.OfferingTag);

NS_SWIFT_NAME(Qonversion.Offering)
@interface QONOffering : NSObject <NSCoding>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign, readonly) QONOfferingTag tag;
@property (nonatomic, copy, readonly) NSArray<QONProduct *> *products;

/**
 Returns Qonversion Product for specific ID from the current offering
 @param productIdentifier - id of the product you want to get from the current offering
 @return Qonversion Product or nil if no product found for the passed identifier
 */
- (nullable QONProduct *)productForIdentifier:(nonnull NSString *)productIdentifier
NS_SWIFT_NAME(product(for:));

@end

NS_ASSUME_NONNULL_END
