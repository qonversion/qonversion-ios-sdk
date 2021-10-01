//
//  XCTestCase+Helpers.h
//  QonversionTests
//
//  Created by Surik Sarkisyan on 16.09.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TestBlock)(NSInvocation *);

@interface XCTestCase (Helpers)

@end

NS_ASSUME_NONNULL_END
