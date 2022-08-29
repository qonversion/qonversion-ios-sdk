#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "XCTestCase+Unmock.h"
#import "XCTestCase+Helpers.h"

#import "QNStoreKitService.h"

@interface QNStoreKitService ()

- (NSArray<SKPaymentTransaction *> *)sortTransactionsByDate:(NSArray<SKPaymentTransaction *> *)transactions;
- (NSDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *)groupTransactions:(NSArray<SKPaymentTransaction *> *)transactions;
- (NSArray<SKPaymentTransaction *> *)filterGroupedTransactions:(NSDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *)groupedTransactionsMap;
- (NSArray<SKPaymentTransaction *> *)filterTransactions:(NSArray<SKPaymentTransaction *> *)transactions;

@end

@interface QNStoreKitServiceTests : XCTestCase

@property (nonatomic, strong) QNStoreKitService *storeKitService;

@end

@implementation QNStoreKitServiceTests

- (void)setUp {
  [super setUp];
  
  self.storeKitService = [QNStoreKitService new];
}

- (void)tearDown {
  self.storeKitService = nil;
  
  [super tearDown];
}

- (void)testSortTransactionsByDate {
  // given
  id firstTransaction = OCMClassMock([SKPaymentTransaction class]);
  id secondTransaction = OCMClassMock([SKPaymentTransaction class]);
  id thirdTransaction = OCMClassMock([SKPaymentTransaction class]);
  
  OCMStub([firstTransaction transactionDate]).andReturn([NSDate dateWithTimeIntervalSince1970:123456789]);
  OCMStub([secondTransaction transactionDate]).andReturn([NSDate dateWithTimeIntervalSince1970:1234567890]);
  OCMStub([thirdTransaction transactionDate]).andReturn([NSDate dateWithTimeIntervalSince1970:1234569999]);
  
  NSArray *transactions = @[secondTransaction, thirdTransaction, firstTransaction];
  
  NSSortDescriptor *dateDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"transactionDate" ascending:YES];
  NSArray *sortDescriptors = [NSArray arrayWithObject:dateDescriptor];
  NSArray *expectedResult = [transactions sortedArrayUsingDescriptors:sortDescriptors];
  
  // when
  NSArray *sortedTransactions = [self.storeKitService sortTransactionsByDate:transactions];
  
  // then
  for (NSUInteger i = 0; i < expectedResult.count; i++) {
    SKPaymentTransaction *expectedTransaction = expectedResult[i];
    SKPaymentTransaction *resultTransaction = sortedTransactions[i];
    XCTAssertEqual(expectedTransaction, resultTransaction);
  }
}

- (void)testGroupTransactions {
  // given
  id transaction1 = OCMClassMock([SKPaymentTransaction class]);
  id transaction2 = OCMClassMock([SKPaymentTransaction class]);
  id transaction3 = OCMClassMock([SKPaymentTransaction class]);
  id transaction4 = OCMClassMock([SKPaymentTransaction class]);
  id transaction5 = OCMClassMock([SKPaymentTransaction class]);
  id transaction6 = OCMClassMock([SKPaymentTransaction class]);
  id transaction7 = OCMClassMock([SKPaymentTransaction class]);
  id transaction8 = OCMClassMock([SKPaymentTransaction class]);
  id transaction9 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction1 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction2 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction3 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction4 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction5 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction6 = OCMClassMock([SKPaymentTransaction class]);
  
  
  OCMStub([transaction2 transactionIdentifier]).andReturn(@"2");
  OCMStub([transaction3 transactionIdentifier]).andReturn(@"3");
  OCMStub([transaction3 originalTransaction]).andReturn(originalTransaction1);
  OCMStub([originalTransaction2 transactionIdentifier]).andReturn(@"4");
  OCMStub([transaction4 originalTransaction]).andReturn(originalTransaction2);
  OCMStub([originalTransaction6 transactionIdentifier]).andReturn(@"6");
  OCMStub([transaction6 originalTransaction]).andReturn(originalTransaction6);
  OCMStub([originalTransaction3 transactionIdentifier]).andReturn(@"8");
  OCMStub([transaction8 originalTransaction]).andReturn(originalTransaction3);
  OCMStub([originalTransaction4 transactionIdentifier]).andReturn(@"9");
  OCMStub([transaction9 originalTransaction]).andReturn(originalTransaction4);
  OCMStub([originalTransaction5 transactionIdentifier]).andReturn(@"2");
  OCMStub([transaction5 originalTransaction]).andReturn(originalTransaction5);
  OCMStub([transaction7 originalTransaction]).andReturn(originalTransaction5);
  
  OCMStub([transaction4 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction5 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction6 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction7 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction8 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction9 transactionIdentifier]).andReturn(@"doesn't matter");
  
  
  NSArray *transactions = @[transaction1, transaction2, transaction3, transaction4, transaction5, transaction6, transaction7, transaction8, transaction9];
  
  NSDictionary *expectedResult = @{
    @"2": @[transaction2, transaction5, transaction7],
    @"3": @[transaction3],
    @"4": @[transaction4],
    @"6": @[transaction6],
    @"8": @[transaction8],
    @"9": @[transaction9]
  };
  
  // when
  NSDictionary *resultTransactions = [self.storeKitService groupTransactions:transactions];
  
  // then
  XCTAssertEqual(expectedResult.count, resultTransactions.count);
  
  for (NSString *key in expectedResult.allKeys) {
    NSArray *expectedArray = expectedResult[key];
    NSArray *resultArray = resultTransactions[key];
    XCTAssertEqual(expectedArray.count, resultArray.count);
    
    for (NSUInteger i; i < expectedArray.count; i++) {
      NSArray *expectedTransaction = expectedArray[i];
      NSArray *resultTransaction = resultArray[i];
      XCTAssertEqual(expectedTransaction, resultTransaction);
    }
  }
}

@end
