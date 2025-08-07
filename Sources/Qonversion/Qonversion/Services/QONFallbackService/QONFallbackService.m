//
//  QONFallbackService.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONFallbackService.h"
#import "QONFallbackObject.h"
#import "QONFallbackMapper.h"

NSString *const kFallbacksFileName = @"qonversion_ios_fallbacks.json";

@interface QONFallbackService ()

@property (nonatomic, strong) QONFallbackMapper *mapper;

@end

@implementation QONFallbackService

- (instancetype)init {
  self = [super init];
  if (self) {
    _mapper = [QONFallbackMapper new];
  }
  return self;
}

- (QONFallbackObject * _Nullable)obtainFallbackData {
  NSBundle *bundle = [NSBundle mainBundle];
  
  NSString *fileName = [kFallbacksFileName stringByDeletingPathExtension];
  NSString *fileExtension = [kFallbacksFileName pathExtension];
  NSString *pathToFile = [bundle pathForResource:fileName ofType:fileExtension];
  
  NSData *fileData = [NSData dataWithContentsOfFile:pathToFile];
  
  if (!fileData) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = paths.firstObject;
    
    if (documentsPath) {
      NSString *filePath = [documentsPath stringByAppendingPathComponent:kFallbacksFileName];
      
      if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        fileData = [NSData dataWithContentsOfFile:filePath];
      } else {
        return nil;
      }
    } else {
      return nil;
    }
  }
  
  NSDictionary *resultMap = [NSJSONSerialization JSONObjectWithData:fileData options:kNilOptions error:nil];
  
  QONFallbackObject *resultObject = [self.mapper mapFallbackData:resultMap];
  
  return resultObject;
}

@end
