//
//  QONPurchaseOptions.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 25.07.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.PurchaseOptions)
/**
 Instances of this class should be used to add additional options to the purchase process.
 */
@interface QONPurchaseOptions : NSObject

// Quantity of product purchasing. Use for consumable in-app products.
@property (nonatomic, assign) NSInteger quantity;

// Context keys associated with a purchase. Use this field to associate a purchase with a concrete remote config.
@property (nonatomic, copy, nullable) NSArray<NSString *> *contextKeys;

/**
 Initialize purchase options with quantity
 */
- (instancetype)initWithQuantity:(NSInteger)quantity NS_SWIFT_UNAVAILABLE("Use swift style initializer instead.");

/**
 Initialize purchase options with quantity and context keys
 */
- (instancetype)initWithQuantity:(NSInteger)quantity contextKeys:(NSArray * _Nullable)contextKeys NS_SWIFT_UNAVAILABLE("Use swift style initializer instead.");

@end

NS_ASSUME_NONNULL_END
