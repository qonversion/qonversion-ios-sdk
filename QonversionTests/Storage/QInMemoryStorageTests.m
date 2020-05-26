#import <XCTest/XCTest.h>
#import "QInMemoryStorage.h"

static NSString *const QInMemoryStorageKey = @"testStorageKey";
NSTimeInterval QDefaultTestTimeout = 0.1;

@interface QInMemoryStorageTests : XCTestCase

@property (nonatomic, strong) QInMemoryStorage *storage;

@end

@implementation QInMemoryStorageTests

- (void)setUp {
    [super setUp];
    self.storage = [QInMemoryStorage new];
}

- (void)tearDown {
    self.storage = nil;
    [super tearDown];
}

- (void)testThatStorageKeepObjectWithoutKey {
    NSObject *expectedObject = [NSObject new];
    
    [self.storage storeObject:expectedObject];
    id resultObject = [self.storage loadObject];
    
    XCTAssertEqualObjects(expectedObject, resultObject);
}

- (void)testThatStorageKeepObjectByKey {
    NSObject *expectedObject = [NSObject new];
    
    [self.storage storeObject:expectedObject forKey:QInMemoryStorageKey];
    id resultObject = [self.storage loadObjectForKey:QInMemoryStorageKey];
    
    XCTAssertEqualObjects(expectedObject, resultObject);
}

- (void)testThatStorageKeepLastValue {
    NSObject *firstObject = [NSObject new];
    NSObject *expectedObject = [NSObject new];
    
    [self.storage storeObject:firstObject];
    [self.storage storeObject:expectedObject];
    id resultObject = [self.storage loadObject];
    
    XCTAssertEqualObjects(expectedObject, resultObject);
}

- (void)testThatStorageRetunNilAfterRemoveObjectWithoutKey {
    NSObject *expectedObject = [NSObject new];
    
    [self.storage storeObject:expectedObject];
    [self.storage removeObject];
    id resultObject = [self.storage loadObject];
    
    XCTAssertNil(resultObject);
}

- (void)testThatStorageReturnNilAfterRemoveObjectByKey {
    NSObject *object = [NSObject new];
    
    [self.storage storeObject:object forKey:QInMemoryStorageKey];
    [self.storage removeObjectForKey:QInMemoryStorageKey];
    id resultObject = [self.storage loadObjectForKey:QInMemoryStorageKey];
    
    XCTAssertNil(resultObject);
}

- (void)testThatStorageReturnObjectWithoutKeyInCompletionBlock {
    NSObject *expectedObject = [NSObject new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion block was called"];
    
    [self.storage storeObject:expectedObject];
    
    __block id resultObject;
    [self.storage loadObjectWithCompletion:^(id object) {
        resultObject = object;
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:QDefaultTestTimeout
                                 handler:^(NSError * _Nullable error) {
                                     XCTAssertEqualObjects(expectedObject, resultObject);
                                 }];
}

- (void)testThatStorageReturnObjectByKeyInCompletionBlock {
    NSObject *expectedObject = [NSObject new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion block was called"];
    
    [self.storage storeObject:expectedObject forKey:QInMemoryStorageKey];
    
    __block id resultObject;
    [self.storage loadObjectForKey:QInMemoryStorageKey withCompletion:^(id object) {
        resultObject = object;
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:QDefaultTestTimeout
                                 handler:^(NSError * _Nullable error) {
                                     XCTAssertEqualObjects(expectedObject, resultObject);
                                 }];
}

@end
