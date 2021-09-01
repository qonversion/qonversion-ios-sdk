#import "QNUserDefaultsStorage.h"
#import "QNKeyedArchiver.h"

static NSString *QNUserDefaultsStorageDefaultKey = @"com.qonversion.io.userDefaultsDefaultKey";

@implementation QNUserDefaultsStorage

- (void)storeObject:(id)object {
  [self storeObject:object forKey:QNUserDefaultsStorageDefaultKey];
}

- (void)storeObject:(id)object forKey:(NSString *)key {
  [self.userDefaults setObject:[QNKeyedArchiver archivedDataWithObject:object] forKey:key];
  [self.userDefaults synchronize];
}

- (void)storeDouble:(double)value forKey:(NSString *)key {
  [self.userDefaults setDouble:value forKey:key];
}

- (id)loadObjectOfClass:(Class)class {
  return [self loadObjectForKey:QNUserDefaultsStorageDefaultKey ofClass:class];
}

- (void)loadObjectWithCompletion:(void (^)(id))completion ofClass:(Class)class {
  [self loadObjectForKey:QNUserDefaultsStorageDefaultKey withCompletion:completion ofClass:class];
}

- (id)loadObjectForKey:(NSString *)key ofClass:(Class)class {
  NSData *data = [self.userDefaults objectForKey:key];
  if (data) {
    return [QNKeyedArchiver unarchiveObjectWithData:data ofClass:class];
  }
  
  return nil;
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
  [self.userDefaults setObject:value forKey:key];
}

- (NSString *)loadStringForKey:(NSString *)key {
  return [self.userDefaults stringForKey:key];
}

- (double)loadDoubleForKey:(NSString *)key {
  return [self.userDefaults doubleForKey:key];
}

- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion ofClass:(Class)class {
  completion([self loadObjectForKey:key ofClass:class]);
}

- (void)removeObject {
  [self removeObjectForKey:QNUserDefaultsStorageDefaultKey];
}

- (void)removeObjectForKey:(NSString *)key {
  [self.userDefaults removeObjectForKey:key];
}

@end
