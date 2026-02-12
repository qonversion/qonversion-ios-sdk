#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNUserDefaultsStorage.h"
#import "QNStoreKitService.h"
#import "QNTestConstants.h"
#import "QONLaunchResult.h"
#import "QONLaunchResult+Protected.h"
#import "QNUserInfoService.h"
#import "QNIdentityManager.h"
#import "QNLocalStorage.h"
#import "QONFallbackService.h"
#import "QONRemoteConfigManager.h"
#import "QONRequestTrigger.h"

@interface QNProductCenterManager (RestoreTestPrivate)

@property (nonatomic) QNStoreKitService *storeKitService;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;
@property (nonatomic) QNAPIClient *apiClient;
@property (nonatomic) QONLaunchResult *launchResult;
@property (nonatomic) NSError *launchError;
@property (nonatomic, assign) BOOL launchingFinished;
@property (nonatomic, assign) BOOL receiptRestoreInProgress;
@property (nonatomic, assign) BOOL restoreInProgress;
@property (nonatomic, assign) BOOL awaitingRestoreResult;

- (void)handleUserSwitchIfNeededWithResult:(QONLaunchResult *)result;

@end

@interface ProductCenterManagerRestoreUserSwitchTests : XCTestCase

@property (nonatomic, strong) id mockClient;
@property (nonatomic, strong) id mockUserInfoService;
@property (nonatomic, strong) id mockRemoteConfigManager;
@property (nonatomic, strong) QNProductCenterManager *manager;

@end

@implementation ProductCenterManagerRestoreUserSwitchTests

- (void)setUp {
  _mockClient = OCMClassMock([QNAPIClient class]);
  OCMStub([_mockClient shared]).andReturn(_mockClient);
  
  _mockUserInfoService = OCMProtocolMock(@protocol(QNUserInfoServiceInterface));
  id mockIdentityManager = OCMClassMock([QNIdentityManager class]);
  id mockLocalStorage = OCMProtocolMock(@protocol(QNLocalStorage));
  id mockFallbackService = OCMClassMock([QONFallbackService class]);
  
  _manager = [[QNProductCenterManager alloc] initWithUserInfoService:_mockUserInfoService
                                                     identityManager:mockIdentityManager
                                                        localStorage:mockLocalStorage
                                                     fallbackService:mockFallbackService];
  [_manager setApiClient:_mockClient];
  
  _mockRemoteConfigManager = OCMClassMock([QONRemoteConfigManager class]);
  _manager.remoteConfigManager = _mockRemoteConfigManager;
}

- (void)tearDown {
  [_mockClient stopMocking];
  _manager = nil;
}

#pragma mark - handleUserSwitchIfNeededWithResult: Tests

- (void)testHandleUserSwitch_SameUid_NoSwitch {
  // Given
  NSString *currentUserId = @"user_123";
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(currentUserId);
  
  QONLaunchResult *launchResult = [[QONLaunchResult alloc] init];
  launchResult.uid = currentUserId;
  
  // Set up reject expectations before the action
  OCMReject([_mockUserInfoService storeIdentity:[OCMArg any]]);
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);
  
  // When
  [_manager handleUserSwitchIfNeededWithResult:launchResult];
  
  // Then - if rejected calls were made, the test would have failed already
  OCMVerifyAll(_mockUserInfoService);
  OCMVerifyAll(_mockRemoteConfigManager);
}

- (void)testHandleUserSwitch_DifferentUid_SwitchOccurs {
  // Given
  NSString *currentUserId = @"user_new";
  NSString *originalUserId = @"user_old";
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(currentUserId);
  
  QONLaunchResult *launchResult = [[QONLaunchResult alloc] init];
  launchResult.uid = originalUserId;
  
  // When
  [_manager handleUserSwitchIfNeededWithResult:launchResult];
  
  // Then
  OCMVerify([_mockUserInfoService storeIdentity:originalUserId]);
  OCMVerify([_mockClient setUserID:originalUserId]);
  OCMVerify([_mockRemoteConfigManager userHasBeenChanged]);
}

- (void)testHandleUserSwitch_NilResult_NoSwitch {
  // Given - set up reject expectations before the action
  OCMReject([_mockUserInfoService storeIdentity:[OCMArg any]]);
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);
  
  // When
  [_manager handleUserSwitchIfNeededWithResult:nil];
  
  // Then
  OCMVerifyAll(_mockUserInfoService);
  OCMVerifyAll(_mockRemoteConfigManager);
}

- (void)testHandleUserSwitch_EmptyUid_NoSwitch {
  // Given
  QONLaunchResult *launchResult = [[QONLaunchResult alloc] init];
  launchResult.uid = @"";
  
  // Set up reject expectations before the action
  OCMReject([_mockUserInfoService storeIdentity:[OCMArg any]]);
  OCMReject([_mockRemoteConfigManager userHasBeenChanged]);
  
  // When
  [_manager handleUserSwitchIfNeededWithResult:launchResult];
  
  // Then
  OCMVerifyAll(_mockUserInfoService);
  OCMVerifyAll(_mockRemoteConfigManager);
}

@end
