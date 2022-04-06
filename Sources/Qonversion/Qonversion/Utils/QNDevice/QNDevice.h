#import <Foundation/Foundation.h>

@interface QNDevice : NSObject

+ (instancetype)current;

@property (readonly, copy, nonatomic) NSString *manufacturer;
@property (readonly, copy, nonatomic) NSString *osName;
@property (readonly, copy, nonatomic) NSString *osVersion;
@property (readonly, copy, nonatomic) NSString *model;
@property (readonly, copy, nonatomic) NSString *appVersion;

@property (readonly, copy, nonatomic) NSString *carrier;
@property (readonly, copy, nonatomic) NSString *country;

@property (readonly, copy, nonatomic) NSString *language;
@property (readonly, copy, nonatomic) NSString *timezone;
@property (readonly, copy, nonatomic) NSString *advertiserID;
@property (readonly, copy, nonatomic) NSString *vendorID;

@property (readonly, copy, nonatomic) NSString *afUserID;
@property (readonly, copy, nonatomic) NSString *adjustUserID;
@property (readonly, copy, nonatomic) NSString *fbAnonID;

@property (readonly, copy, nonatomic) NSString *installDate;
@property (readonly, copy, nonatomic) NSString *pushNotificationsToken;

- (BOOL)isPushTokenProcessed;
- (void)setPushTokenProcessed:(BOOL)processed;

- (void)setPushNotificationsToken:(NSString *)token;

@end
