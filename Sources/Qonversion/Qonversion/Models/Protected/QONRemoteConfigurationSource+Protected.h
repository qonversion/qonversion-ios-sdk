//
//  QONRemoteConfigInfo+Protected.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 30.08.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigurationSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigurationSource ()

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                              type:(QONRemoteConfigurationSourceType)type
                    assignmentType:(QONRemoteConfigurationAssignmentType)assignmentType
                        contextKey:(NSString *)contextKey;

@end

NS_ASSUME_NONNULL_END
