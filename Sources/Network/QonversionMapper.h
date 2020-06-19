#import <Foundation/Foundation.h>
#import "QonversionCheckResult.h"
#import "QonversionLaunchResult.h"

typedef NS_ENUM(NSInteger, QErrorCode) {
    QErrorCodeFailedReceiveData = 0,
    QErrorCodeFailedParseResponse,
    QErrorCodeIncorrectRequest
};

@interface QonversionCheckResultComposeModel : NSObject

@property (nonatomic, nullable) QonversionCheckResult *result;
@property (nonatomic, copy, nullable) NSError *error;

@end


@interface QonversionMapper : NSObject

- (QonversionCheckResultComposeModel * _Nonnull)composeModelFrom:(NSData * _Nullable)data;
- (QonversionCheckResult * _Nullable)fillCheckResultWith:(NSDictionary * _Nullable)dict;
- (QonversionLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary *)dict;

+ (NSError * _Nonnull)error:(NSString * _Nullable)message code:(QErrorCode)errorCode;

@end
