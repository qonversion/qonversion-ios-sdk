//
//  QNActionsService.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNAPIClient, QNScreensMapper, QNAutomationScreen;

typedef void (^QNActiveAutomationsCompletionHandler)(NSArray<NSString *> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.AutomationCompletionHandler);
typedef void (^QNAutomationsCompletionHandler)(QNAutomationScreen *screen, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.AutomationCompletionHandler);

NS_ASSUME_NONNULL_BEGIN

@interface QNAutomationsService : NSObject

@property (nonatomic, strong) QNAPIClient *apiClient;
@property (nonatomic, strong) QNScreensMapper *mapper;

- (void)automationWithID:(NSString *)automationID completion:(QNAutomationsCompletionHandler)completion;
- (void)trackScreenShownWithID:(NSString *)automationID;
- (void)obtainAutomationScreensWithCompletion:(QNActiveAutomationsCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
