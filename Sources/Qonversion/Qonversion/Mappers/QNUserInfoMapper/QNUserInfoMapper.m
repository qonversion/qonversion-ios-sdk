//
//  QNUserInfoMapper.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 19.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNUserInfoMapper.h"
#import "QNUser+Protected.h"

@interface QNUserInfoMapper ()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *platformTypes;

@end

@implementation QNUserInfoMapper

- (QNUser *)mapUserInfo:(NSDictionary *)data {
  NSDictionary *userData = [self getDataFromObject:data];

  NSString *userID = userData[@"id"];
  NSString *originalAppVersion = userData[@"originalAppVersion"];
  
  QNUser *user = [[QNUser alloc] initWithID:userID
                         originalAppVersion:originalAppVersion];
  
  return user;
}

- (NSDictionary *)getDataFromObject:(NSDictionary *)obj {
  NSDictionary *temp = obj[@"data"];
  
  NSDictionary *result = [temp isKindOfClass:[NSDictionary class]] ? temp : nil;
  
  return result;
}

@end
