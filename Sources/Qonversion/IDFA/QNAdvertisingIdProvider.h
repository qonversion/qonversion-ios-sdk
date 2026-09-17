//
//  QNAdvertisingIdProvider.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 25.08.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads the advertising identifier (IDFA) through `ASIdentifierManager`.
///
/// This class is the only place in the SDK that touches the identifier, and it ships separately from the core:
/// the `NoIdfa` CocoaPods subspec excludes this folder and the `QonversionNoIdfa` Swift package product leaves the
/// `QonversionIDFA` target out. The core never imports this header — `QNDevice` looks the class up at runtime with
/// `NSClassFromString` and treats its absence as "IDFA prohibited" (Kids Mode).
@interface QNAdvertisingIdProvider : NSObject

/// The advertising identifier, or `nil` when it is unavailable or all zeros (tracking denied).
+ (nullable NSString *)obtainAdvertisingID;

@end

NS_ASSUME_NONNULL_END
