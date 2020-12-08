#import "QNUserDefaultsStorage.h"

static NSString *QNUserDefaultsStorageDefaultKey = @"com.qonversion.io.userDefaultsDefaultKey";

@implementation QNUserDefaultsStorage

- (void)storeObject:(id)object {
  [self storeObject:object forKey:QNUserDefaultsStorageDefaultKey];
}

- (void)storeObject:(id)object forKey:(NSString *)key {
  [self.userDefaults setObject:[self archivedDataWith:object] forKey:key];
  [self.userDefaults synchronize];
}

- (id)loadObject {
  return [self loadObjectForKey:QNUserDefaultsStorageDefaultKey];
}

- (void)loadObjectWithCompletion:(void (^)(id))completion {
  [self loadObjectForKey:QNUserDefaultsStorageDefaultKey withCompletion:completion];
}

- (id)loadObjectForKey:(NSString *)key {
  NSData *data = [self.userDefaults objectForKey:key];
  if (data) {
    return [self unarchiveObjectWithData:data];
  }
  
  return nil;
}

- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion([self loadObjectForKey:key]);
}

- (void)removeObject {
  [self removeObjectForKey:QNUserDefaultsStorageDefaultKey];
}

- (void)removeObjectForKey:(NSString *)key {
  [self.userDefaults removeObjectForKey:key];
}

- (NSData *)archivedDataWith:(id)object {
  return [NSKeyedArchiver archivedDataWithRootObject:object];
}

- (id)unarchiveObjectWithData:(NSData *)data {
  return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}

@end
