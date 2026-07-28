//
//  QNUserPropertiesManagerTests.m
//  QonversionTests
//
//  Created by Surik Sarkisyan on 17.09.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNUserPropertiesManager.h"
#import "QNAPIClient.h"
#import "QNInMemoryStorage.h"

/*
 * Contract tests for the forceSendProperties waiter guarantee (DEV-1231).
 *
 * The remote-config path wraps every network fetch in
 * -forceSendProperties: and only issues the GET from the completion, so the
 * completion must fire strictly AFTER the buffered properties actually reached
 * the API — including the two historically leaky windows:
 *   1) the buffer is empty only because an in-flight POST drained it;
 *   2) a force flush lands while a POST is in flight (follow-up send).
 */

@interface QNUserPropertiesManager (FlushContractPrivate)

@property (nonatomic) QNAPIClient *apiClient;
@property (nonatomic) QNInMemoryStorage *inMemoryStorage;
@property (atomic, strong) NSMutableArray<QONUserPropertiesEmptyCompletionHandler> *completionBlocks;
@property (atomic, assign) BOOL sendingScheduled;
@property (atomic, assign) BOOL updatingCurrently;
@property (atomic, assign) BOOL forceResendRequired;

- (void)sendProperties:(BOOL)force;

@end

@interface QNUserPropertiesManagerTests : XCTestCase

@property (nonatomic, strong) id mockClient;
@property (nonatomic, strong) QNUserPropertiesManager *manager;

@end

@implementation QNUserPropertiesManagerTests

- (void)setUp {
  [super setUp];

  self.mockClient = OCMClassMock([QNAPIClient class]);
  OCMStub([self.mockClient shared]).andReturn(self.mockClient);
  OCMStub([self.mockClient apiKey]).andReturn(@"test_api_key");

  self.manager = [QNUserPropertiesManager new];
  [self.manager setApiClient:self.mockClient];
}

- (void)tearDown {
  // The manager's init schedules collectIntegrationsDataInBackground with a 5s
  // performSelector that retains it past tearDown — cancel it so the delayed
  // fire cannot message a stopMocking'd class mock mid-suite.
  [NSObject cancelPreviousPerformRequestsWithTarget:self.manager];
  [self.mockClient stopMocking];
  self.mockClient = nil;
  self.manager = nil;

  [super tearDown];
}

- (void)testForceSendCompletesImmediatelyWhenIdleAndEmpty {
  // given - nothing pending, nothing in flight

  // when
  __block BOOL completionFired = NO;
  [self.manager forceSendProperties:^{
    completionFired = YES;
  }];

  // then - the flush is trivially done, synchronously
  XCTAssertTrue(completionFired);
  XCTAssertEqual(self.manager.completionBlocks.count, 0);
}

- (void)testForceSendWithEmptyBufferAndInFlightPostQueuesTheWaiter {
  // given - a POST is in flight and has already drained the buffer (hole #1)
  self.manager.updatingCurrently = YES;

  // when
  __block BOOL completionFired = NO;
  [self.manager forceSendProperties:^{
    completionFired = YES;
  }];

  // then - the waiter must NOT be released synchronously: it waits for a real
  // request completion; the follow-up intent is recorded atomically with the
  // enqueue
  XCTAssertFalse(completionFired);
  XCTAssertEqual(self.manager.completionBlocks.count, 1);
  XCTAssertTrue(self.manager.forceResendRequired);
}

- (void)testEmptySendDrainsQueuedWaiters {
  // given - a waiter queued behind an in-flight POST that finished without
  // leaving anything to send
  self.manager.updatingCurrently = YES;
  XCTestExpectation *waiterReleased = [self expectationWithDescription:@"waiter released"];
  [self.manager forceSendProperties:^{
    [waiterReleased fulfill];
  }];

  // when - the next send finds an empty buffer
  self.manager.updatingCurrently = NO;
  [self.manager sendProperties:NO];

  // then - the empty branch releases the waiter instead of stranding it, and
  // clears the stale follow-up intent
  [self waitForExpectations:@[waiterReleased] timeout:2.0];
  XCTAssertFalse(self.manager.forceResendRequired);
}

- (void)testForceFlushDuringInFlightPostTriggersFollowUpBeforeReleasingWaiters {
  // given - the API captures completions so the test controls request timing
  __block void (^firstCompletion)(NSDictionary *, NSError *) = nil;
  __block void (^secondCompletion)(NSDictionary *, NSError *) = nil;
  XCTestExpectation *firstPost = [self expectationWithDescription:@"first POST started"];
  XCTestExpectation *secondPost = [self expectationWithDescription:@"follow-up POST started"];
  __block NSInteger postCount = 0;
  OCMStub([self.mockClient sendProperties:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained void (^completion)(NSDictionary *, NSError *) = nil;
    [invocation getArgument:&completion atIndex:3];
    postCount += 1;
    if (postCount == 1) {
      firstCompletion = [completion copy];
      [firstPost fulfill];
    } else {
      secondCompletion = [completion copy];
      [secondPost fulfill];
    }
  });

  [self.manager.inMemoryStorage storeObject:@"a" forKey:@"key_a"];
  [self.manager forceSendProperties:^{}];
  [self waitForExpectations:@[firstPost] timeout:2.0];

  // when - a property lands and a force flush arrives while POST-1 is in flight
  [self.manager.inMemoryStorage storeObject:@"b" forKey:@"key_b"];
  __block BOOL waiterFired = NO;
  [self.manager forceSendProperties:^{
    waiterFired = YES;
  }];
  XCTAssertTrue(self.manager.forceResendRequired);

  // POST-1 completes successfully - the follow-up POST must start with the
  // leftover property while the waiter stays queued (hole #2)
  firstCompletion(@{}, nil);
  [self waitForExpectations:@[secondPost] timeout:2.0];
  XCTAssertFalse(waiterFired);

  // then - only the follow-up completion releases the waiter
  secondCompletion(@{}, nil);
  XCTAssertTrue(waiterFired);
}

@end
