#import <Foundation/Foundation.h>

@interface QNDevice : NSObject

+ (instancetype)current;

@property (readonly, strong, nonatomic) NSString *manufacturer;
@property (readonly, strong, nonatomic) NSString *osName;
@property (readonly, strong, nonatomic) NSString *osVersion;
@property (readonly, strong, nonatomic) NSString *model;
@property (readonly, strong, nonatomic) NSString *appVersion;

@property (readonly, strong, nonatomic) NSString *carrier;
@property (readonly, strong, nonatomic) NSString *country;

@property (readonly, strong, nonatomic) NSString *language;
@property (readonly, strong, nonatomic) NSString *timezone;
@property (readonly, strong, nonatomic) NSString *advertiserID;
@property (readonly, strong, nonatomic) NSString *vendorID;

@property (readonly, strong, nonatomic) NSString *afUserID;
@property (readonly, strong, nonatomic) NSString *adjustUserID;
@property (readonly, strong, nonatomic) NSString *fbAnonID;

@property (readonly, strong, nonatomic) NSString *installDate;

@end
