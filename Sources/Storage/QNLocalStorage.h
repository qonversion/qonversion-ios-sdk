#import "QNUtils.h"
#import <Foundation/Foundation.h>

@protocol QNLocalStorage <NSObject>
@required
- (void)storeObject:(id)object;

- (void)storeObject:(id)object
             forKey:(NSString *)key;

- (id)loadObject;
- (void)loadObjectWithCompletion:(void (^)(id))completion;

- (id)loadObjectForKey:(NSString *)key;
- (void)loadObjectForKey:(NSString *)key
          withCompletion:(void(^)(id))completion;

- (void)removeObject;
- (void)removeObjectForKey:(NSString *)key;

@optional
- (void)setVersion:(NSString *)version;
- (NSString *)version;

- (void)clear;

@end
