#import <Foundation/Foundation.h>
#import "QNLaunchResult.h"

typedef NS_ENUM(NSInteger, QNErrorCode) {
  QNErrorCodeFailedReceiveData = 0,
  QNErrorCodeFailedParseResponse,
  QNErrorCodeIncorrectRequest
};

@interface QonversionComposeModel : NSObject <NSCoding>

@property (nonatomic, copy, nullable) NSError *error;

@end

@interface QonversionLaunchComposeModel : NSObject <NSCoding>

@property (nonatomic, copy, nullable) NSError *error;
@property (nonatomic, strong, nullable) QNLaunchResult *result;

@end

@interface QNMapper : NSObject

- (QonversionLaunchComposeModel * _Nonnull)composeLaunchModelFrom:(NSData * _Nullable)data;

- (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;
- (NSDictionary <NSString *, QNPermission *> * _Nonnull)fillPermissions:(NSDictionary * _Nullable)dict;

+ (NSError * _Nonnull)error:(NSString * _Nullable)message code:(QNErrorCode)errorCode;

@end
