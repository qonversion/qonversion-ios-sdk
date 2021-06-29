//
//  QNOffering.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 05.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNProduct;
@class QNExperimentInfo;

NS_ASSUME_NONNULL_BEGIN

static NSString *const kOfferingByIDWasCalledNotificationName = @"OfferingForIDNotification";

typedef NS_ENUM(NSInteger, QNOfferingTag) {
  QNOfferingTagNone = 0,
  /**
   Provides access to content on a recurring basis with a free introductory offer
   */
  QNOfferingTagMain = 1
} NS_SWIFT_NAME(Qonversion.OfferingTag);

NS_SWIFT_NAME(Qonversion.Offering)
@interface QNOffering : NSObject <NSCoding>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign, readonly) QNOfferingTag tag;
@property (nonatomic, copy, readonly) NSArray<QNProduct *> *products;
@property (nonatomic, strong, nullable, readonly) QNExperimentInfo *experimentInfo;

- (nullable QNProduct *)productForIdentifier:(NSString *)productIdentifier;

@end

NS_ASSUME_NONNULL_END
