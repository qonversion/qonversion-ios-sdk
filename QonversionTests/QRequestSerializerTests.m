#import <XCTest/XCTest.h>
#import "QNRequestSerializer.h"
#import "QONStoreKit2PurchaseModel.h"

@interface QNRequestSerializerTests : XCTestCase

@property (nonatomic, strong) QNRequestSerializer *serializer;

@end

@implementation QNRequestSerializerTests

- (void)setUp {
    [super setUp];

    self.serializer = [[QNRequestSerializer alloc] init];
}

- (void)testThatLaunchDataCorrect {
    id launchData = self.serializer.launchData;
    XCTAssertTrue([launchData isKindOfClass:[NSDictionary class]]);
    XCTAssertNotNil(launchData);
}

- (QONStoreKit2PurchaseModel *)baseStoreKit2Model {
    QONStoreKit2PurchaseModel *model = [QONStoreKit2PurchaseModel new];
    model.productId = @"com.qonversion.test.monthly";
    model.price = @"9.99";
    model.currency = @"USD";
    model.transactionId = @"1000000000000001";
    model.originalTransactionId = @"1000000000000001";
    model.subscriptionPeriodUnit = @"2";
    model.subscriptionPeriodNumberOfUnits = @"1";

    return model;
}

- (void)testThatStoreKit2PaidIntroReportsIntroductoryPrice {
    QONStoreKit2PurchaseModel *model = [self baseStoreKit2Model];
    model.introductoryPrice = @"1.99";
    model.introductoryNumberOfPeriods = @"1";
    model.introductoryPeriodNumberOfUnits = @"1";
    model.introductoryPeriodUnit = @"2";
    model.introductoryPaymentMode = @"1";

    NSDictionary *data = [self.serializer purchaseInfo:model receipt:nil];
    NSDictionary *introOffer = data[@"introductory_offer"];

    XCTAssertNotNil(introOffer);
    XCTAssertEqualObjects(introOffer[@"value"], @"1.99");
    XCTAssertNotEqualObjects(introOffer[@"value"], model.price);
}

- (void)testThatStoreKit2FreeTrialReportsZeroIntroductoryPrice {
    QONStoreKit2PurchaseModel *model = [self baseStoreKit2Model];
    model.introductoryPrice = @"0";
    model.introductoryNumberOfPeriods = @"1";
    model.introductoryPeriodNumberOfUnits = @"7";
    model.introductoryPeriodUnit = @"0";
    model.introductoryPaymentMode = @"2";

    NSDictionary *data = [self.serializer purchaseInfo:model receipt:nil];
    NSDictionary *introOffer = data[@"introductory_offer"];

    XCTAssertNotNil(introOffer);
    XCTAssertEqualObjects(introOffer[@"value"], @"0");
}

- (void)testThatStoreKit2NoIntroOmitsIntroductoryOffer {
    QONStoreKit2PurchaseModel *model = [self baseStoreKit2Model];

    NSDictionary *data = [self.serializer purchaseInfo:model receipt:nil];

    XCTAssertNil(data[@"introductory_offer"]);
}

@end
