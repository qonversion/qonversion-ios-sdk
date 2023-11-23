//
//  QONPromoPurchasesDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 07.10.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//
#import "QONLaunchResult.h"

NS_SWIFT_NAME(Qonversion.PromoPurchasesDelegate)
@protocol QONPromoPurchasesDelegate <NSObject>

/**
 This method is called when a user initiates a promotional in-app purchase from the App Store. Run the execution block in this method if your app can handle a purchase at the current time. Or you can cache the executionBlock, and call it when the app is ready to make the purchase.
 Before define this method be sure [Qonversion setPromoPurchasesDelegate:] called
 If you are not using QNPromoPurchasesDelegate purchase will proceed automatically
 @param productID            StoreKit product identifier
 @param executionBlock purchase execution block
 */
- (void)shouldPurchasePromoProductWithIdentifier:(nonnull NSString *)productID executionBlock:(nonnull QONPromoPurchaseCompletionHandler)executionBlock;

@end
