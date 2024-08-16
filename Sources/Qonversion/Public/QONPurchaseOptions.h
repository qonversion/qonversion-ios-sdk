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
 Initialize purchase options with quantity.
 @param quantity quantity of product purchasing. Use for consumable in-app products.
 @return QONPurchaseOptions instance
 */
- (instancetype)initWithQuantity:(NSInteger)quantity NS_SWIFT_UNAVAILABLE("Use swift style initializer instead.");

/**
 Initialize purchase options with quantity and context keys.
 @param quantity quantity of product purchasing. Use for consumable in-app products.
 @param contextKeys context keys associated with a purchase. Use this field to associate a purchase with a concrete remote config.
 @return QONPurchaseOptions instance
 */
- (instancetype)initWithQuantity:(NSInteger)quantity contextKeys:(NSArray<NSString *> * _Nullable)contextKeys NS_SWIFT_UNAVAILABLE("Use swift style initializer instead.");

/**
 Initialize purchase options with context keys.
 @param contextKeys context keys associated with a purchase. Use this field to associate a purchase with a concrete remote config.
 @return QONPurchaseOptions instance
 */
- (instancetype)initWithContextKeys:(NSArray<NSString *> * _Nullable)contextKeys NS_SWIFT_UNAVAILABLE("Use swift style initializer instead.");

@end

NS_ASSUME_NONNULL_END
