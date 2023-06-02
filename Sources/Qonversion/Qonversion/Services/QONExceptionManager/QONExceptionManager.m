//
// Created by Kamo Spertsyan on 31.05.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONExceptionManager.h"
#import "QNUtils.h"
#import "QNAPIClient.h"

NSString *const kCrashLogFileSuffix = @".qonversion.stacktrace";

@interface QNExceptionManagerUtils : NSObject

+ (BOOL)isQonversionException:(NSException * _Nonnull)exception;

+ (void)storeException:(NSException * _Nonnull)exception;

@end

@implementation QNExceptionManagerUtils

+ (BOOL)isQonversionException:(NSException *)exception {
    NSString *appName = [[[NSBundle mainBundle] executablePath] lastPathComponent];
    NSString *pattern = @"\\S+\\s+(\\S+)";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];

    NSArray *callStackSymbols = [exception callStackSymbols];
    for (NSString *callStackSymbol in callStackSymbols) {
        NSTextCheckingResult *result = [regex firstMatchInString:callStackSymbol options:0 range:NSMakeRange(0, callStackSymbol.length)];
        if (result.numberOfRanges > 1) {
            NSString *binaryName = [callStackSymbol substringWithRange:[result rangeAtIndex:1]];

            if ([binaryName isEqualToString:@"Qonversion"]) {
                return YES;
            }
            if ([binaryName isEqualToString:appName]) {
                return NO;
            }
        }
    }

    return NO;
}

+ (void)storeException:(NSException *)exception {
    NSArray *backtrace = [exception callStackSymbols];
    NSString *rawStackTrace = [backtrace componentsJoinedByString:@"\n"];
    NSString *reason = [exception reason] ?: @"";
    NSString *name = [exception name];
    NSDictionary *userInfo = [exception userInfo] ?: @{};

    NSDictionary *crashInfo = @{
            @"rawStackTrace": rawStackTrace,
            @"elements": backtrace,
            @"name": name,
            @"message": reason,
            @"title": [NSString stringWithFormat:@"%@: %@", name, reason],
            @"userInfo": userInfo
    };

    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:crashInfo options:0 error:&error];
    if (error) {
        QONVERSION_LOG(@"Error converting crash information to JSON: %@", error);
        return;
    }
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    NSString *uuidString = [[NSUUID UUID] UUIDString];
    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSince1970];
    NSString *filename = [NSString stringWithFormat:@"%@-%g%@", uuidString, timeInterval, kCrashLogFileSuffix];
    NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *filePath = [documentsDirectory stringByAppendingPathComponent:filename];

    BOOL success = [jsonString writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!success) {
        QONVERSION_LOG(@"Error saving crash information: %@", error);
    }
}

@end

static NSUncaughtExceptionHandler *defaultExceptionHandler = nil;

static void uncaughtExceptionHandler(NSException * _Nonnull exception) {
    BOOL isQonversionException = [QNExceptionManagerUtils isQonversionException:exception];
    if (isQonversionException) {
        [QNExceptionManagerUtils storeException:exception];
    }

    if (defaultExceptionHandler != nil) {
        defaultExceptionHandler(exception);
    }
}

@implementation QONExceptionManager

- (void)initialize {
#if DEBUG
    return;
#endif

    _apiClient = [QNAPIClient shared];

    defaultExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(uncaughtExceptionHandler);

    __block __weak QONExceptionManager *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf sendCrashReportsInBackground];
    });
}

- (void)sendCrashReportsInBackground {
    NSArray *filenames = [self getAvailableReportFilenames];
    for (NSURL *fileURL in filenames) {
        NSDictionary *crashData = [self getContentOfCrashReport:fileURL.path];
        if (crashData == nil) {
            continue;
        }

        NSDictionary *data = @{
                @"exception": crashData,
        };

        [[self apiClient] sendCrashReport:data completion:^(NSDictionary *dict, NSError *error) {
            if (error) {
                QONVERSION_LOG(@"Error sending crash information to API: %@", error);
            } else {
                [self removeCrashReportFile:fileURL.path];
            }
        }];
    }
}

- (NSArray *)getAvailableReportFilenames {
    NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *directoryURL = [NSURL fileURLWithPath:documentsDirectory];

    NSMutableArray<NSURL *> *foundFileURLs = [NSMutableArray array];

    NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsSubdirectoryDescendants;
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:directoryURL
                                          includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                             options:options
                                                        errorHandler:nil];

    for (NSURL *fileURL in enumerator) {
        NSString *filename = nil;
        [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];

        if ([filename hasSuffix:kCrashLogFileSuffix]) {
            [foundFileURLs addObject:fileURL];
        }
    }

    return [foundFileURLs copy];
}

- (NSDictionary *)getContentOfCrashReport:(NSString *)reportFilename {
    NSString *crashInfoJson = [NSString stringWithContentsOfFile:reportFilename encoding:NSUTF8StringEncoding error:nil];
    NSData *jsonData = [crashInfoJson dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (error) {
        QONVERSION_LOG(@"Error reading data from crash report: %@", error);
        return nil;
    }

    return dictionary;
}

- (void)removeCrashReportFile:(NSString *)reportFilename {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    if ([fileManager fileExistsAtPath:reportFilename]) {
        BOOL success = [fileManager removeItemAtPath:reportFilename error:&error];
        if (!success) {
            QONVERSION_LOG(@"Error removing crash report file: %@", error);
        }
    } else {
        QONVERSION_LOG(@"Crash report file not found at path: %@", reportFilename);
    }
}

@end
