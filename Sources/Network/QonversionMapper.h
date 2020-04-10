#import <Foundation/Foundation.h>
#import "QonversionCheckResult.h"

typedef NS_ENUM(NSInteger, QErrorCode) {
    QErrorCodeFailedReceiveData = 0,
    QErrorCodeFailedParseResponse,
    QErrorCodeIncorrectResponse
};

@interface QonversionCheckResultComposeModel : NSObject

@property (copy, nullable) QonversionCheckResult *result;
@property (copy, nullable) NSError *error;

@end


@interface QonversionMapper : NSObject

- (QonversionCheckResultComposeModel *)composeModelFrom:(NSData *)data;
- (QonversionCheckResult *)fillCheckResultWith:(NSDictionary *)dict;

+ (NSError *)error:(NSString *)message code:(QErrorCode)errorCode;

@end
