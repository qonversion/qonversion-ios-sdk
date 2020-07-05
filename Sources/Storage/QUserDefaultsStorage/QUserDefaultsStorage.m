#import "QUserDefaultsStorage.h"

static NSString *QUserDefaultsStorageDefaultKey = @"com.qonversion.io.userDefaultsDefaultKey";

@implementation QUserDefaultsStorage

- (void)storeObject:(id)object {
  [self storeObject:object forKey:QUserDefaultsStorageDefaultKey];
}

- (void)storeObject:(id)object forKey:(NSString *)key {
  [self.userDefaults setObject:[self archivedDataWith:object] forKey:key];
  [self.userDefaults synchronize];
}

- (id)loadObject {
  return [self loadObjectForKey:QUserDefaultsStorageDefaultKey];
}

- (void)loadObjectWithCompletion:(void (^)(id))completion {
  [self loadObjectForKey:QUserDefaultsStorageDefaultKey withCompletion:completion];
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
  [self removeObjectForKey:QUserDefaultsStorageDefaultKey];
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
