#import <XCTest/XCTest.h>
#import "QNInMemoryStorage.h"

static NSString *const QNInMemoryStorageKey = @"testStorageKey";
NSTimeInterval QDefaultTestTimeout = 0.1;

@interface QNInMemoryStorageTests : XCTestCase

@property (nonatomic, strong) QNInMemoryStorage *storage;

@end

@implementation QNInMemoryStorageTests

- (void)setUp {
    [super setUp];
    self.storage = [QNInMemoryStorage new];
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
    
    [self.storage storeObject:expectedObject forKey:QNInMemoryStorageKey];
    id resultObject = [self.storage loadObjectForKey:QNInMemoryStorageKey];
    
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
    
    [self.storage storeObject:object forKey:QNInMemoryStorageKey];
    [self.storage removeObjectForKey:QNInMemoryStorageKey];
    id resultObject = [self.storage loadObjectForKey:QNInMemoryStorageKey];
    
    XCTAssertNil(resultObject);
}

- (void)testThatStorageReturnObjectWithoutKeyInCompletionHandler {
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

- (void)testThatStorageReturnObjectByKeyInCompletionHandler {
    NSObject *expectedObject = [NSObject new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion block was called"];
    
    [self.storage storeObject:expectedObject forKey:QNInMemoryStorageKey];
    
    __block id resultObject;
    [self.storage loadObjectForKey:QNInMemoryStorageKey withCompletion:^(id object) {
        resultObject = object;
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:QDefaultTestTimeout
                                 handler:^(NSError * _Nullable error) {
                                     XCTAssertEqualObjects(expectedObject, resultObject);
                                 }];
}

@end
