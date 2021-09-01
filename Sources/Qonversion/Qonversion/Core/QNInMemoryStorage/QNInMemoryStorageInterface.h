//
//  QNInMemoryStorageInterface.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 01.09.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QNInMemoryStorageInterface <NSObject>

- (void)storeObject:(id)object;

- (void)storeObject:(id)object
             forKey:(NSString *)key;

- (id)loadObject;
- (void)loadObjectWithCompletion:(void (^)(id))completion;

- (id)loadObjectForKey:(NSString *)key;
- (void)loadObjectForKey:(NSString *)key
          withCompletion:(void(^)(id))completion;

- (void)removeObject;
- (void)removeObjectForKey:(NSString *)key;

@optional
- (void)setVersion:(NSString *)version;
- (NSString *)version;
- (void)storeDouble:(double)value forKey:(NSString *)key;
- (double)loadDoubleForKey:(NSString *)key;

- (void)setString:(NSString *)value forKey:(NSString *)key;
- (NSString *)loadStringForKey:(NSString *)key;

- (void)clear;

@end
