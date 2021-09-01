//
//  QNKeyedArchiver.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 31.08.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNKeyedArchiver.h"

@implementation QNKeyedArchiver

+ (nullable NSData *)archivedDataWithObject:(nonnull id)object {
  NSData *data;
  
  if (@available(macOS 10.13, iOS 11.0, watchOS 5.0, tvOS 11.0, *)) {
    data = [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:NO error:nil];
  } else {
    data = [NSKeyedArchiver archivedDataWithRootObject:object];
  }
  
  return data;
}

+ (nullable id)unarchiveObjectWithData:(nonnull NSData *)data ofClass:(nonnull Class)class {
  id object;

  if (@available(macOS 10.13, iOS 11.0, watchOS 5.0, tvOS 11.0, *)) {
    object = [NSKeyedUnarchiver unarchivedObjectOfClass:class fromData:data error:nil];
  } else {
    object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
  }

  return object;
}

@end
