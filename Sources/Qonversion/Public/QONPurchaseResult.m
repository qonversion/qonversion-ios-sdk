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

- (instancetype)initWithStatus:(QONPurchaseResultStatus)status
                  entitlements:(nullable NSDictionary<NSString *, QONEntitlement *> *)entitlements
                   transaction:(nullable SKPaymentTransaction *)transaction
                         error:(nullable NSError *)error
                        source:(QONPurchaseResultSource)source {
    self = [super init];
    if (self) {
        _status = status;
        _entitlements = entitlements;
        _transaction = transaction;
        _error = error;
        _source = source;
    }
    return self;
}

- (BOOL)isFallbackGenerated {
    return _source == QONPurchaseResultSourceLocal;
}

- (BOOL)isSuccessful {
    return _status == QONPurchaseResultStatusSuccess;
}

- (BOOL)isCanceledByUser {
    return _status == QONPurchaseResultStatusUserCanceled;
}

- (BOOL)isPending {
    return _status == QONPurchaseResultStatusPending;
}

- (BOOL)isError {
    return _status == QONPurchaseResultStatusError;
}

// MARK: - Static Factory Methods

+ (instancetype)successWithEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements
                             transaction:(SKPaymentTransaction *)transaction {
    return [[self alloc] initWithStatus:QONPurchaseResultStatusSuccess
                           entitlements:entitlements
                            transaction:transaction
                                  error:nil
                                 source:QONPurchaseResultSourceApi];
}

+ (instancetype)successFromFallbackWithEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements
                                          transaction:(SKPaymentTransaction *)transaction {
    return [[self alloc] initWithStatus:QONPurchaseResultStatusSuccess
                           entitlements:entitlements
                            transaction:transaction
                                  error:nil
                                 source:QONPurchaseResultSourceLocal];
}

+ (instancetype)userCanceled {
    return [[self alloc] initWithStatus:QONPurchaseResultStatusUserCanceled
                           entitlements:nil
                            transaction:nil
                                  error:nil
                                 source:QONPurchaseResultSourceApi];
}

+ (instancetype)pending {
    return [[self alloc] initWithStatus:QONPurchaseResultStatusPending
                           entitlements:nil
                            transaction:nil
                                  error:nil
                                 source:QONPurchaseResultSourceApi];
}

+ (instancetype)errorWithError:(NSError *)error {
    return [[self alloc] initWithStatus:QONPurchaseResultStatusError
                           entitlements:nil
                            transaction:nil
                                  error:error
                                 source:QONPurchaseResultSourceApi];
}

@end
