#import "QNInMemoryStorage.h"

static NSString *QNInMemoryStorageDefaultKey = @"inMemoryStorageDefaultKey";

@interface QNInMemoryStorage ()

@property (nonatomic, copy) NSString *version;

@end

@implementation QNInMemoryStorage

+ (instancetype)sharedInstance {
  static QNInMemoryStorage *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [QNInMemoryStorage new];
  });
  return sharedInstance;
}

- (NSDictionary *)storageDictionary {
  if (_storageDictionary == nil) {
    _storageDictionary = [NSDictionary new];
  }
  return _storageDictionary;
}

- (void)storeObject:(id)object {
  [self storeObject:object forKey:QNInMemoryStorageDefaultKey];
}

- (void)storeObject:(id)object forKey:(NSString *)key {
  NSMutableDictionary *tempDictionary = [self.storageDictionary mutableCopy];
  [tempDictionary setValue:object forKey:key];
  self.storageDictionary = tempDictionary;
}

- (id)loadObject {
  return [self loadObjectForKey:QNInMemoryStorageDefaultKey];
}

- (id)loadObjectForKey:(NSString *)key {
  return self.storageDictionary[key];
}

- (void)loadObjectWithCompletion:(void (^)(id))completion {
  [self loadObjectForKey:QNInMemoryStorageDefaultKey
          withCompletion:completion];
}

- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  id object = [self loadObjectForKey:key];
  run_block(completion, object);
}

- (void)removeObject {
  [self removeObjectForKey:QNInMemoryStorageDefaultKey];
}

- (void)clear {
  self.storageDictionary = [NSDictionary new];
}

- (void)removeObjectForKey:(NSString *)key {
  NSMutableDictionary *tempDictionary = [self.storageDictionary mutableCopy];
  [tempDictionary removeObjectForKey:key];
  self.storageDictionary = tempDictionary;
}

@end
