//
//  QONFallbacksService.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONFallbacksService.h"
#import "QONFallbackObject.h"
#import "QONFallbacksMapper.h"

NSString *const kFallbacksFileName = @"qonversion_fallbacks.json";

@interface QONFallbacksService ()

@property (nonatomic, strong) QONFallbacksMapper *mapper;

@end

@implementation QONFallbacksService

- (instancetype)init {
  self = [super init];
  if (self) {
    _mapper = [QONFallbacksMapper new];
  }
  return self;
}

- (QONFallbackObject * _Nullable)obtainFallbackData {
  NSBundle *bundle = [NSBundle mainBundle];
  
  NSString *fileName = [kFallbacksFileName stringByDeletingPathExtension];
  NSString *fileExtension = [kFallbacksFileName pathExtension];
  NSString *pathToFile = [bundle pathForResource:fileName ofType:fileExtension];
  
  NSData *fileData = [NSData dataWithContentsOfFile:pathToFile];
  
  NSDictionary *resultMap = [NSJSONSerialization JSONObjectWithData:fileData options:kNilOptions error:nil];
  
  QONFallbackObject *resultObject = [self.mapper mapFallback:resultMap];
  
  return resultObject;
}

@end
