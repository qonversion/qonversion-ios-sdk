//
//  QONPurchaseResult.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONPurchaseResult.h"
#import "QONPurchaseResult+Protected.h"
#import "QONEntitlement.h"

@implementation QONPurchaseResult

- (instancetype)initWithEntitlements:(nullable NSDictionary<NSString *, QONEntitlement *> *)entitlements
                         transaction:(nullable SKPaymentTransaction *)transaction {
    return [self initWithEntitlements:entitlements
                                error:nil
                          transaction:transaction
                      isUserCanceled:NO];
}

- (instancetype)initWithError:(nullable NSError *)error
               isUserCanceled:(BOOL)isUserCanceled {
    return [self initWithEntitlements:nil
                                error:error
                          transaction:nil
                      isUserCanceled:isUserCanceled];
}

- (instancetype)initWithError:(nullable NSError *)error
                   transaction:(nullable SKPaymentTransaction *)transaction
               isUserCanceled:(BOOL)isUserCanceled {
    return [self initWithEntitlements:nil
                                error:error
                          transaction:transaction
                      isUserCanceled:isUserCanceled];
}

- (instancetype)initWithEntitlements:(nullable NSDictionary<NSString *, QONEntitlement *> *)entitlements
                               error:(nullable NSError *)error
                         transaction:(nullable SKPaymentTransaction *)transaction
                     isUserCanceled:(BOOL)isUserCanceled {
    self = [super init];
    if (self) {
        _entitlements = entitlements;
        _error = error;
        _transaction = transaction;
        _isUserCanceled = isUserCanceled;
    }
    return self;
}

@end
