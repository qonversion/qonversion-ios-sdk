#import <Foundation/Foundation.h>
#import "QNLaunchResult.h"

@interface QNMapper : NSObject

- (QNLaunchResult * _Nonnull)fillLaunchResult:(NSDictionary * _Nullable)dict;
- (NSDictionary <NSString *, QNPermission *> * _Nonnull)fillPermissions:(NSDictionary * _Nullable)dict;

@end
