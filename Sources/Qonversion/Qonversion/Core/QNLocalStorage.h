#import "QNUtils.h"
#import <Foundation/Foundation.h>

@protocol QNLocalStorage <NSObject>
@required

- (void)storeObject:(id)object
             forKey:(NSString *)key;

- (id)loadObjectForKey:(NSString *)key;
- (void)loadObjectForKey:(NSString *)key
          withCompletion:(void(^)(id))completion;

- (void)removeObjectForKey:(NSString *)key;

@optional
- (void)storeBool:(BOOL)value forKey:(NSString *)key;
- (BOOL)loadBoolforKey:(NSString *)key;
- (void)setVersion:(NSString *)version;
- (NSString *)version;
- (void)storeDouble:(double)value forKey:(NSString *)key;
- (double)loadDoubleForKey:(NSString *)key;

- (void)setString:(NSString *)value forKey:(NSString *)key;
- (NSString *)loadStringForKey:(NSString *)key;

- (void)clear;

@end
