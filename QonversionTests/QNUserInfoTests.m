#import <XCTest/XCTest.h>

#import "QNUserInfo.h"
#import "QNConstants.h"

@interface QNUserInfoTests : XCTestCase

@end

@implementation QNUserInfoTests

- (void)testReceiptInfo {
    XCTAssertNil(QNUserInfo.appStoreReceipt);
}

@end
