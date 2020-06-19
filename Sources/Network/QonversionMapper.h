#import <Foundation/Foundation.h>
#import "QonversionCheckResult.h"
#import "QonversionLaunchResult.h"

typedef NS_ENUM(NSInteger, QErrorCode) {
    QErrorCodeFailedReceiveData = 0,
    QErrorCodeFailedParseResponse,
    QErrorCodeIncorrectRequest
};

@interface QonversionComposeModel : NSObject

@property (nonatomic, copy, nullable) NSError *error;

@end

@interface QonversionCheckResultComposeModel : QonversionComposeModel

@property (nonatomic, nullable) QonversionCheckResult *result;

@end

@interface QonversionLaunchComposeModel : QonversionComposeModel

@property (nonatomic, nullable) QonversionLaunchResult *result;

@end

@interface QonversionMapper : NSObject

- (QonversionCheckResultComposeModel * _Nonnull)composeModelFrom:(NSData * _Nullable)data;
- (QonversionLaunchComposeModel * _Nonnull)composeLaunchModelFrom:(NSData * _Nullable)data;

- (QonversionCheckResult * _Nullable)fillCheckResultWith:(NSDictionary * _Nullable)dict;
- (QonversionLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;
- (NSDictionary <NSString *, QonversionPermission *> * _Nonnull)fillPermissions:(NSDictionary * _Nullable)dict;

+ (NSError * _Nonnull)error:(NSString * _Nullable)message code:(QErrorCode)errorCode;

@end
