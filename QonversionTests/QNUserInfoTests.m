#import <XCTest/XCTest.h>

#import "QNUserInfo.h"
#import "QNInternalConstants.h"

@interface QNUserInfoTests : XCTestCase

@end

@implementation QNUserInfoTests

- (void)testReceiptInfo {
  XCTAssertNotNil(QNUserInfo.appStoreReceipt);
  XCTAssertTrue([QNUserInfo.appStoreReceipt isEqualToString:@""]);
}

@end
