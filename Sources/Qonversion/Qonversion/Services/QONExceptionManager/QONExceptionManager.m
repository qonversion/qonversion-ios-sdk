//
// Created by Kamo Spertsyan on 31.05.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONExceptionManager.h"
#import "QNUtils.h"
#import "QNAPIClient.h"

NSString *const kCrashLogFileSuffix = @".qonversion.stacktrace";
NSString *const kStackTraceLinePartsPattern = @"\\S+\\s+(\\S+)";
NSString *const kSdkBinaryName = @"Qonversion";
NSString *const kDefaultExceptionReason = @"Unknown reason";

static NSUncaughtExceptionHandler *defaultExceptionHandler = nil;

static void uncaughtExceptionHandler(NSException * _Nonnull exception) {
  BOOL isSpm = NO;
  BOOL isQonversionException = [[QONExceptionManager shared] isQonversionException:exception isSpm:&isSpm];
  if (isQonversionException) {
    [[QONExceptionManager shared] storeException:exception isSpm:isSpm];
  }
  
  if (defaultExceptionHandler) {
    defaultExceptionHandler(exception);
  }
}

@implementation QONExceptionManager

- (instancetype)init {
  self = [super init];
  
  if (self) {
#if DEBUG
    return self;
#endif
    
    _apiClient = [QNAPIClient shared];
    
    defaultExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(uncaughtExceptionHandler);
    
    [self sendCrashReportsInBackground];
  }
  
  return self;
}

+ (instancetype)shared {
  static id shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [self new];
  });
  
  return shared;
}

- (BOOL)isQonversionException:(NSException *)exception isSpm:(BOOL *)isSpm {
  NSString *appName = [[[NSBundle mainBundle] executablePath] lastPathComponent];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kStackTraceLinePartsPattern options:0 error:nil];
  
  NSArray<NSString *> *callStackSymbols = [exception callStackSymbols];
  for (NSString *callStackSymbol in callStackSymbols) {
    NSTextCheckingResult *result = [regex firstMatchInString:callStackSymbol options:0 range:NSMakeRange(0, callStackSymbol.length)];
    if (result.numberOfRanges > 1) {
      NSString *binaryName = [callStackSymbol substringWithRange:[result rangeAtIndex:1]];
      
      if ([binaryName isEqualToString:kSdkBinaryName]) {
        *isSpm = NO;
        return YES;
      }
      if ([binaryName isEqualToString:appName]) {
        NSArray<NSString *> *const kQonversionClassPrefixes = @[@"Qonversion", @"QON", @"QN"];
        for (NSString *prefix in kQonversionClassPrefixes) {
          NSString *entry = [NSString stringWithFormat:@"-[%@", prefix];
          NSRange range = [callStackSymbol rangeOfString:entry];

          if (range.location != NSNotFound) {
            *isSpm = YES;
            return YES;
          }
        }
        return NO;
      }
    }
  }
  
  return NO;
}

- (void)storeException:(NSException *)exception isSpm:(BOOL)isSpm {
  NSArray<NSString *> *backtrace = [exception callStackSymbols];
  NSString *rawStackTrace = [backtrace componentsJoinedByString:@"\n"];
  NSString *reason = [exception reason] ?: kDefaultExceptionReason;
  NSExceptionName name = [exception name];
  NSDictionary *userInfo = [exception userInfo] ?: @{};
  
  NSMutableDictionary *crashInfo = [NSMutableDictionary new];
  
  crashInfo[@"rawStackTrace"] = rawStackTrace;
  crashInfo[@"elements"] = backtrace;
  crashInfo[@"name"] = name;
  crashInfo[@"message"] = reason;
  crashInfo[@"isSpm"] = @(isSpm);
  crashInfo[@"title"] = [NSString stringWithFormat:@"%@: %@", name, reason];
  crashInfo[@"userInfo"] = userInfo;

  NSError *error;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:crashInfo options:0 error:&error];
  if (error) {
    QONVERSION_LOG(@"Error converting crash information to JSON: %@", error);
    return;
  }
  NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
  
  NSString *uuidString = [NSUUID UUID].UUIDString;
  NSTimeInterval timeInterval = [[NSDate date] timeIntervalSince1970];
  NSString *filename = [NSString stringWithFormat:@"%@-%g%@", uuidString, timeInterval, kCrashLogFileSuffix];
  NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString *filePath = [documentsDirectory stringByAppendingPathComponent:filename];
  
  if (!filePath) {
    QONVERSION_LOG(@"Failed to find file path to save crash information: %@", filename);
    return;
  }

  BOOL success = [jsonString writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
  if (!success) {
    QONVERSION_LOG(@"Error saving crash information: %@", error);
  }
}

- (void)sendCrashReportsInBackground {
  __block __weak QONExceptionManager *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    NSArray<NSURL *> *filenames = [weakSelf obtainAvailableReportFilenames];
    for (NSURL *fileURL in filenames) {
      NSDictionary *crashData = [weakSelf contentOfCrashReport:fileURL.path];
      if (!crashData) {
        continue;
      }
      
      NSDictionary *data = @{
        @"exception": crashData,
      };
      
      [weakSelf.apiClient sendCrashReport:data completion:^(NSError *error) {
        if (error) {
          QONVERSION_LOG(@"Error sending crash information to API: %@", error);
        } else {
          [weakSelf removeCrashReportFile:fileURL.path];
        }
      }];
    }
  });
}

- (NSArray<NSURL *> *)obtainAvailableReportFilenames {
  NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  if (!documentsDirectory) {
    QONVERSION_LOG(@"Failed to find documents directory with crash information files");
    return @[];
  }

  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSURL *directoryURL = [NSURL fileURLWithPath:documentsDirectory];
  
  if (!directoryURL) {
    QONVERSION_LOG(@"Failed to find documents directory URL to retrieve crash information files");
    return @[];
  }

  NSMutableArray<NSURL *> *foundFileURLs = [NSMutableArray new];
  
  NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsSubdirectoryDescendants;
  NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:directoryURL
                                        includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                           options:options
                                                      errorHandler:nil];
  
  for (NSURL *fileURL in enumerator) {
    NSString *filename;
    [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];
    
    if ([filename hasSuffix:kCrashLogFileSuffix]) {
      [foundFileURLs addObject:fileURL];
    }
  }
  
  return [foundFileURLs copy];
}

- (NSDictionary *)contentOfCrashReport:(NSString *)reportFilename {
  NSError *error;
  NSString *crashInfoJson = [NSString stringWithContentsOfFile:reportFilename encoding:NSUTF8StringEncoding error:&error];
  
  if (error) {
    QONVERSION_LOG(@"Error reading data from crash report: %@. Filename: %@", error, reportFilename);
    return nil;
  }
  
  NSData *jsonData = [crashInfoJson dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
  if (error) {
    QONVERSION_LOG(@"Error reading data from crash report: %@. Filename: %@", error, reportFilename);
    return nil;
  }
  
  return dictionary;
}

- (void)removeCrashReportFile:(NSString *)reportFilename {
  NSFileManager *fileManager = [NSFileManager defaultManager];
  if ([fileManager fileExistsAtPath:reportFilename]) {
    NSError *error;
    BOOL success = [fileManager removeItemAtPath:reportFilename error:&error];
    if (!success) {
      QONVERSION_LOG(@"Error removing crash report file: %@. Filename: %@", error, reportFilename);
    }
  } else {
    QONVERSION_LOG(@"Crash report file not found at path: %@", reportFilename);
  }
}

@end
