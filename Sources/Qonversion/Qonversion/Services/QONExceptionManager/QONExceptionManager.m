//
// Created by Kamo Spertsyan on 31.05.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import "QONExceptionManager.h"
#import "QNUtils.h"

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
            @"rawStackTrace" : rawStackTrace,
            @"elements" : backtrace,
            @"name" : name,
            @"message" : reason,
            @"userInfo" : userInfo
    };

    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:crashInfo options:NSJSONWritingPrettyPrinted error:&error];
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
    if (success) {
        QONVERSION_LOG(@"Crash information saved to file: %@", filePath);
    } else {
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
    defaultExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(uncaughtExceptionHandler);
}

@end
