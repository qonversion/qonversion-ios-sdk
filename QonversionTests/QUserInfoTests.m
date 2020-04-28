#import <XCTest/XCTest.h>

#import "UserInfo.h"
#import "QConstants.h"

@interface QUserInfoTests : XCTestCase

@end

@implementation QUserInfoTests

- (void)testReceiptInfo {
    XCTAssertNil(UserInfo.appStoreReceipt);
}

@end
