//
//  QNActionsService.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNAPIClient.h"

typedef void (^QNActionsCompletionHandler)(NSDictionary *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ActionsCompletionHandler);

NS_ASSUME_NONNULL_BEGIN

@interface QNActionsService : NSObject

@property (nonatomic, strong) QNAPIClient *apiClient;

- (void)actionWithID:(NSString *)actionID completion:(QNActionsCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
