#import <Foundation/Foundation.h>
#import "QNLaunchResult.h"

@class QonversionLaunchComposeModel;

@interface QNMapper : NSObject

- (QonversionLaunchComposeModel * _Nonnull)composeLaunchModelFrom:(NSData * _Nullable)data;

- (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;
- (NSDictionary <NSString *, QNPermission *> * _Nonnull)fillPermissions:(NSDictionary * _Nullable)dict;

@end
