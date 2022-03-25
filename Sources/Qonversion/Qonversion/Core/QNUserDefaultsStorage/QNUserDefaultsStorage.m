#import "QNUserDefaultsStorage.h"
#import "QNKeyedArchiver.h"

static NSString *QNUserDefaultsStorageDefaultKey = @"com.qonversion.io.userDefaultsDefaultKey";

@implementation QNUserDefaultsStorage

- (void)storeObject:(id)object {
  [self storeObject:object forKey:QNUserDefaultsStorageDefaultKey];
}

- (void)storeObject:(id)object forKey:(NSString *)key {
  NSData *archivedData = [QNKeyedArchiver archivedDataWithObject:object];
  [self.userDefaults setObject:archivedData forKey:key];
  [self.userDefaults synchronize];
}

- (void)storeBool:(BOOL)value forKey:(NSString *)key {
  [self.userDefaults setBool:value forKey:key];
}

- (BOOL)loadBoolforKey:(NSString *)key {
  return [self.userDefaults boolForKey:key];
}

- (void)storeDouble:(double)value forKey:(NSString *)key {
  [self.userDefaults setDouble:value forKey:key];
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
    return [QNKeyedArchiver unarchiveObjectWithData:data];
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

- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion([self loadObjectForKey:key]);
}

- (void)removeObject {
  [self removeObjectForKey:QNUserDefaultsStorageDefaultKey];
}

- (void)removeObjectForKey:(NSString *)key {
  [self.userDefaults removeObjectForKey:key];
}

@end
