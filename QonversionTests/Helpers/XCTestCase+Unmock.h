//
//  XCTestCase+Unmock.h
//  QonversionTests
//
//  Created by Surik Sarkisyan on 19.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCTestCase (Unmock)

- (void)unmock:(id)object;

@end

NS_ASSUME_NONNULL_END
