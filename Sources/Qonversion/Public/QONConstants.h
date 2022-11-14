#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#define DID_ENTER_BACKGROUND_NOTIFICATION_NAME NSApplicationDidResignActiveNotification
#elif TARGET_OS_IOS || TARGET_OS_TV
#define DID_ENTER_BACKGROUND_NOTIFICATION_NAME UIApplicationDidEnterBackgroundNotification
#elif TARGET_OS_WATCH
#define DID_ENTER_BACKGROUND_NOTIFICATION_NAME NSExtensionHostDidEnterBackgroundNotification
#endif

#if TARGET_OS_IOS || TARGET_OS_TV
#define UI_DEVICE 1
#else
#define UI_DEVICE 0
#endif

extern NSString *const keyQInternalUserID;
extern NSString *const keyQUnknownLibrary;
extern NSString *const keyQUnknownVersion;
extern NSString *const keyQONPropertyReg;
extern NSString *const keyQSource;
extern NSString *const keyQSourceVersion;

// MARK: - Qonversion Underhood User Properties

extern NSString *const keyQONPropertyFacebookAnonUserID;

extern NSString *const keyQONErrorDomain;
extern NSString *const keyQONAPIErrorDomain;
extern NSString *const kQNPlatform;
extern NSString *const kQNOSName;
