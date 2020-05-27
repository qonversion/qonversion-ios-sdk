#import <Foundation/Foundation.h>

extern NSString *const keyQInternalUserID;
extern NSString *const keyQVersion;
extern NSString *const keyQUnknownLibrary;
extern NSString *const keyQUnknownVersion;
extern NSString *const keyQPlatform;
extern NSString *const keyQOSName;
extern NSString *const keyQPropertyReg;
extern int const kQPropertiesSendingPeriodInSeconds;

typedef NS_ENUM(NSInteger, QProperty) {
    QPropertyEmail = 0,
    QPropertyName,
    QPropertyPremium
};

// MARK: - Qonversion Underhood User Properties

extern NSString *const keyQPropertyFacebookAnonUserID;
extern NSString *const keyQPropertyAppsFlyerUserID;
extern NSString *const keyQPropertyAdjustADID;
