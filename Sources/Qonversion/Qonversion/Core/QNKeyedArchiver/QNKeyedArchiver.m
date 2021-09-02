//
//  QNKeyedArchiver.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 31.08.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNKeyedArchiver.h"

@implementation QNKeyedArchiver

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
+ (nullable NSData *)archivedDataWithObject:(nonnull id)object {
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object];
  
  return data;
}

+ (nullable id)unarchiveObjectWithData:(nonnull NSData *)data {
  id object = [NSKeyedUnarchiver unarchiveObjectWithData:data];

  return object;
}
#pragma GCC diagnostic pop

@end
