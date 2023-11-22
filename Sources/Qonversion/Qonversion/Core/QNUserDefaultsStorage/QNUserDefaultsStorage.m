#import "QNUserDefaultsStorage.h"
#import "QNKeyedArchiver.h"

@implementation QNUserDefaultsStorage

- (void)storeObject:(id)object forKey:(NSString *)key {
  NSData *archivedData = [QNKeyedArchiver archivedDataWithObject:object];
  [self.customUserDefaults setObject:archivedData forKey:key];
  [self.userDefaults setObject:archivedData forKey:key];
}

- (void)storeBool:(BOOL)value forKey:(NSString *)key {
  [self.customUserDefaults setBool:value forKey:key];
  [self.userDefaults setBool:value forKey:key];
}

- (BOOL)loadBoolforKey:(NSString *)key {
  BOOL result = NO;
  if (self.customUserDefaults) {
    result = [self.customUserDefaults boolForKey:key];
    if (!result) {
      result = [self.userDefaults boolForKey:key];
      [self.customUserDefaults setBool:result forKey:key];
    }
  } else {
    result = [self.userDefaults boolForKey:key];
  }
  
  return result;
}

- (void)storeDouble:(double)value forKey:(NSString *)key {
  [self.customUserDefaults setDouble:value forKey:key];
  [self.userDefaults setDouble:value forKey:key];
}

- (id)loadObjectForKey:(NSString *)key {
  NSData *data;
  if (self.customUserDefaults) {
    data = [self.customUserDefaults objectForKey:key];
    if (!data) {
      data = [self.userDefaults objectForKey:key];
      
      [self.customUserDefaults setObject:data forKey:key];
    }
  } else {
    data = [self.userDefaults objectForKey:key];
  }
  
  if (data) {
    return [QNKeyedArchiver unarchiveObjectWithData:data];
  }
  
  return nil;
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
  [self.customUserDefaults setObject:value forKey:key];
  [self.userDefaults setObject:value forKey:key];
}

- (NSString *)loadStringForKey:(NSString *)key {
  NSString *result;
  if (self.customUserDefaults) {
    result = [self.customUserDefaults stringForKey:key];
    
    if (!result) {
      result = [self.userDefaults stringForKey:key];
      [self.customUserDefaults setObject:result forKey:key];
    }
  } else {
    result = [self.userDefaults stringForKey:key];
  }
  
  return result;
}

- (double)loadDoubleForKey:(NSString *)key {
  double result;
  if (self.customUserDefaults) {
    result = [self.customUserDefaults doubleForKey:key];
    
    if (result == 0.0) {
      result = [self.userDefaults doubleForKey:key];
      [self.customUserDefaults setDouble:result forKey:key];
    }
  } else {
    result = [self.userDefaults doubleForKey:key];
  }
  
  return result;
}

- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion([self loadObjectForKey:key]);
}

- (void)removeObjectForKey:(NSString *)key {
  [self.customUserDefaults removeObjectForKey:key];
  [self.userDefaults removeObjectForKey:key];
}

@end
