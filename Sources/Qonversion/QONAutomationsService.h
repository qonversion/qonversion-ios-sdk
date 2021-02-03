//
//  QONActionsService.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNAPIClient, QONAutomationsMapper, QONAutomationsScreen, QNUserActionPoint;

NS_ASSUME_NONNULL_BEGIN

typedef void (^QNActiveAutomationCompletionHandler)(NSArray<QNUserActionPoint *> *actionPoints, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.AutomationCompletionHandler);
typedef void (^QNAutomationsCompletionHandler)(QONAutomationsScreen *screen, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.AutomationCompletionHandler);

@interface QONAutomationsService : NSObject

@property (nonatomic, strong) QNAPIClient *apiClient;
@property (nonatomic, strong) QONAutomationsMapper *mapper;

- (void)automationWithID:(NSString *)automationID completion:(QNAutomationsCompletionHandler)completion;
- (void)trackScreenShownWithID:(NSString *)automationID;
- (void)obtainAutomationScreensWithCompletion:(QNActiveAutomationCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
