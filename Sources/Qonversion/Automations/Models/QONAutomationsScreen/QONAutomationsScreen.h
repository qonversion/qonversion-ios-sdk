//
//  QONAutomationsScreen.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.12.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QONAutomationsScreen : NSObject

@property (nonatomic, copy, readonly) NSString *screenID;
@property (nonatomic, copy, readonly) NSString *htmlString;

- (instancetype)initWithIdentifier:(NSString *)identifier htmlString:(NSString *)html;

@end

NS_ASSUME_NONNULL_END
