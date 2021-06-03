//
//  QNPurchase+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 20.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNPurchase.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNPurchase (Protected)

- (instancetype)initWithUserID:(NSString *)userID
                    originalID:(NSString *)originalID
                    purchaseToken:(NSString *)purchaseToken
                      platform:(QNPurchasePlatform)platform
              platformRawValue:(NSString *)platformRawValue
             platformProductID:(NSString *)platformProductID
                       product:(QNUserProduct *)product
                      currency:(NSString *)currency
                        amount:(NSUInteger)amount
                  purchaseDate:(NSDate *)purchaseDate
                    createDate:(NSDate *)createDate
                        object:(NSString *)object;

@end

NS_ASSUME_NONNULL_END
