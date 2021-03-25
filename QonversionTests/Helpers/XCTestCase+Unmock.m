//
//  XCTestCase+Unmock.m
//  QonversionTests
//
//  Created by Surik Sarkisyan on 19.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "XCTestCase+Unmock.h"
#import <OCMock/OCMock.h>

@implementation XCTestCase (Unmock)

- (void)unmock:(id)object {
  [object stopMocking];
  object = nil;
}

@end
