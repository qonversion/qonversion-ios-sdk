#ifndef QBlocksHelpers_h
#define QBlocksHelpers_h

#define run_block(block, ...) block ? block(__VA_ARGS__) : nil
#define run_block_on_main(block, ...) if(block){\
if ([NSThread isMainThread]) {\
run_block(block, __VA_ARGS__);\
}\
else{\
dispatch_async(dispatch_get_main_queue(), ^{run_block(block,__VA_ARGS__);});\
}\
}

#define run_block_on_bg(block, ...) if(block){\
if (![NSThread isMainThread]) {\
block(__VA_ARGS__);\
}\
else{\
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{run_block(block,__VA_ARGS__);});\
}\
}


#endif

#ifndef QONVERSION_DEBUG
#define QONVERSION_DEBUG 1
#endif

#ifndef QONVERSION_LOG
#if QONVERSION_DEBUG
#   define QONVERSION_LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#   define QONVERSION_LOG(...)
#endif
#endif

#ifndef QONVERSION_LOG_ERRORS
#define QONVERSION_LOG_ERRORS 1
#endif

#ifndef QONVERSION_ERROR
#if QONVERSION_LOG_ERRORS
#   define QONVERSION_ERROR(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#   define QONVERSION_ERROR(...)
#endif
#endif

#import <Foundation/Foundation.h>
#import "QNErrors.h"

@interface QNUtils : NSObject

+ (BOOL)isEmptyString:(NSString *)string;
+ (NSString *)convertHexData:(NSData *)tokenData;
+ (BOOL)isMoreThanDayAgo:(NSTimeInterval)timeInterval;

@end
