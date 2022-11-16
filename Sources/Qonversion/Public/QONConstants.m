#import "QONConstants.h"

NSString *const keyQUnknownLibrary = @"unknown";
NSString *const keyQUnknownVersion = @"unknown";
NSString *const keyQInternalUserID = @"keyQInternalUserID";
NSString *const keyQONPropertyReg = @"(?=.*[a-zA-Z])^[-a-zA-Z0-9_.:]+$";
NSString *const keyQSource = @"com.qonversion.keys.source";
NSString *const keyQSourceVersion = @"com.qonversion.keys.sourceVersion";

NSString *const keyQONPropertyFacebookAnonUserID = @"_q_fb_anon_id";

NSString * const keyQONErrorDomain = @"com.qonversion.io";
NSString * const keyQONAPIErrorDomain = @"com.qonversion.io.api";

#if TARGET_OS_OSX
    NSString *const kQNPlatform = @"macOS";
    NSString *const kQNOSName = @"macos";
#elif TARGET_OS_TV
    NSString *const kQNPlatform = @"tvOS";
    NSString *const kQNOSName = @"tvos";
#elif TARGET_OS_MACCATALYST
    NSString *const kQNPlatform = @"macCatalyst";
    NSString *const kQNOSName = @"macCatalyst";
#elif TARGET_OS_WATCH
    NSString *const kQNPlatform = @"watchOS";
    NSString *const kQNOSName = @"watchOS";
#else // iOS, simulator, etc.
    NSString *const kQNPlatform = @"iOS";
    NSString *const kQNOSName = @"ios";
#endif