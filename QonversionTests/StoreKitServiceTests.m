#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "XCTestCase+Unmock.h"
#import "XCTestCase+Helpers.h"

#import "QNStoreKitService.h"

@interface StoreKitTestsMocks : NSObject

@property (nonatomic, copy) NSDictionary *groupedTransactions;
@property (nonatomic, copy) NSArray *transactions;
@property (nonatomic, copy) NSArray *filteredGroupedTransactions;

@end

@implementation StoreKitTestsMocks

@end

@interface MockTransactionWithDate : NSObject

@property (nonatomic, strong) NSDate *transactionDate;

@end

@implementation MockTransactionWithDate

@end

@interface QNStoreKitService ()

- (NSArray<SKPaymentTransaction *> *)sortTransactionsByDate:(NSArray *)transactions;
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
  MockTransactionWithDate *firstTransaction = [MockTransactionWithDate new];
  MockTransactionWithDate *secondTransaction = [MockTransactionWithDate new];
  MockTransactionWithDate *thirdTransaction = [MockTransactionWithDate new];
  firstTransaction.transactionDate = [NSDate dateWithTimeIntervalSince1970:123456789];
  secondTransaction.transactionDate = [NSDate dateWithTimeIntervalSince1970:1234567890];
  thirdTransaction.transactionDate = [NSDate dateWithTimeIntervalSince1970:1234569999];
  
  NSArray *transactions = @[secondTransaction, thirdTransaction, firstTransaction];
  
  NSSortDescriptor *dateDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"transactionDate" ascending:YES];
  NSArray *sortDescriptors = [NSArray arrayWithObject:dateDescriptor];
  NSArray *expectedResult = [transactions sortedArrayUsingDescriptors:sortDescriptors];
  
  // when
  NSArray *sortedTransactions = [self.storeKitService sortTransactionsByDate:transactions];
  
  // then
  for (NSUInteger i = 0; i < expectedResult.count; i++) {
    id expectedTransaction = expectedResult[i];
    id resultTransaction = sortedTransactions[i];
    XCTAssertEqual(expectedTransaction, resultTransaction);
  }
}

- (void)testGroupTransactions {
  // given
  StoreKitTestsMocks *mocks = [self prepareExpectedResult];
  NSDictionary *expectedResult = mocks.groupedTransactions;
  
  // when
  NSDictionary *resultTransactions = [self.storeKitService groupTransactions:mocks.transactions];
  
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

- (void)testGroupedTransactions {
  // given
  StoreKitTestsMocks *mocks = [self prepareExpectedResult];
  NSArray *expectedFilteredTransactions = mocks.filteredGroupedTransactions;
  
  // when
  NSArray<SKPaymentTransaction *> *result = [self.storeKitService filterGroupedTransactions:mocks.groupedTransactions];
  
  // then
  XCTAssertEqual(expectedFilteredTransactions.count, result.count);
  
  for (SKPaymentTransaction *transaction in expectedFilteredTransactions) {
    XCTAssertTrue([result containsObject:transaction]);
  }
}

- (StoreKitTestsMocks *)prepareExpectedResult {
  id payment1 = OCMClassMock([SKPayment class]);
  id payment2 = OCMClassMock([SKPayment class]);
  id payment3 = OCMClassMock([SKPayment class]);
  
  id transaction1 = OCMClassMock([SKPaymentTransaction class]);
  id transaction2 = OCMClassMock([SKPaymentTransaction class]); // it's original transaction for transactions 5 and 7. Field originalTransaction is empty
  id transaction3 = OCMClassMock([SKPaymentTransaction class]);
  id transaction4 = OCMClassMock([SKPaymentTransaction class]);
  id transaction5 = OCMClassMock([SKPaymentTransaction class]);
  id transaction6 = OCMClassMock([SKPaymentTransaction class]); // nonconsumable
  id transaction7 = OCMClassMock([SKPaymentTransaction class]);
  id transaction8 = OCMClassMock([SKPaymentTransaction class]);
  id transaction9 = OCMClassMock([SKPaymentTransaction class]);
  id transaction10 = OCMClassMock([SKPaymentTransaction class]);
  
  id originalTransaction1 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction2 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction3 = OCMClassMock([SKPaymentTransaction class]);
  id originalTransaction4 = OCMClassMock([SKPaymentTransaction class]);
  
  OCMStub([payment1 productIdentifier]).andReturn(@"weekly");
  OCMStub([payment2 productIdentifier]).andReturn(@"monthly");
  OCMStub([payment3 productIdentifier]).andReturn(@"nonconsumable");
  
  OCMStub([transaction2 payment]).andReturn(payment1);
  OCMStub([transaction5 payment]).andReturn(payment2);
  OCMStub([transaction7 payment]).andReturn(payment1);
  OCMStub([transaction8 payment]).andReturn(payment1);
  OCMStub([transaction10 payment]).andReturn(payment1);
  
  OCMStub([transaction3 payment]).andReturn(payment1);
  OCMStub([transaction4 payment]).andReturn(payment2);
  OCMStub([transaction6 payment]).andReturn(payment3);
  
  OCMStub([originalTransaction2 transactionIdentifier]).andReturn(@"4");
  OCMStub([originalTransaction3 transactionIdentifier]).andReturn(@"8");
  OCMStub([originalTransaction4 transactionIdentifier]).andReturn(@"9");
  
  OCMStub([transaction2 transactionIdentifier]).andReturn(@"2");
  OCMStub([transaction3 transactionIdentifier]).andReturn(@"3");
  OCMStub([transaction6 transactionIdentifier]).andReturn(@"6");
  
  OCMStub([transaction3 originalTransaction]).andReturn(originalTransaction1);
  OCMStub([transaction4 originalTransaction]).andReturn(originalTransaction2);
  OCMStub([transaction8 originalTransaction]).andReturn(originalTransaction3);
  OCMStub([transaction10 originalTransaction]).andReturn(originalTransaction3);
  OCMStub([transaction9 originalTransaction]).andReturn(originalTransaction4);
  OCMStub([transaction5 originalTransaction]).andReturn(transaction2);
  OCMStub([transaction7 originalTransaction]).andReturn(transaction2);
  
  OCMStub([transaction4 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction5 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction7 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction8 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction9 transactionIdentifier]).andReturn(@"doesn't matter");
  OCMStub([transaction10 transactionIdentifier]).andReturn(@"doesn't matter");
  
  NSArray *transactions = @[transaction1, transaction2, transaction3, transaction4, transaction5, transaction6, transaction7, transaction8, transaction9, transaction10];
  
  NSDictionary *groupedTransactions = @{
    @"2": @[transaction2, transaction5, transaction7],
    @"3": @[transaction3],
    @"4": @[transaction4],
    @"6": @[transaction6],
    @"8": @[transaction8, transaction10],
    @"9": @[transaction9]
  };
  
  NSArray *filteredGroupedTransactions = @[transaction2, transaction5, transaction7, transaction3, transaction4, transaction6, transaction8, transaction9];
  
  StoreKitTestsMocks *result = [StoreKitTestsMocks new];
  result.transactions = transactions;
  result.groupedTransactions = groupedTransactions;
  result.filteredGroupedTransactions = filteredGroupedTransactions;
  
  return result;
}

@end
