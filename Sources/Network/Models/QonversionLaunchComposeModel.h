#import <Foundation/Foundation.h>

@class QNLaunchResult;

NS_ASSUME_NONNULL_BEGIN

@interface QonversionLaunchComposeModel : NSObject <NSCoding>

@property (nonatomic, copy, nullable) NSError *error;
@property (nonatomic, strong, nullable) QNLaunchResult *result;

@end

NS_ASSUME_NONNULL_END
