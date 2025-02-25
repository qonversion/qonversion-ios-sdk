#import "QNInMemoryStorage.h"

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

- (instancetype)init
{
  self = [super init];
  if (self) {
    _storageDictionary = [NSDictionary new];
  }
  return self;
}

- (void)storeObject:(id)object forKey:(NSString *)key {
  NSMutableDictionary *tempDictionary = [self.storageDictionary mutableCopy];
  [tempDictionary setValue:object forKey:key];
  self.storageDictionary = [tempDictionary copy];
}

- (id)loadObjectForKey:(NSString *)key {
  return self.storageDictionary[key];
}

- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  id object = [self loadObjectForKey:key];
  run_block(completion, object);
}

- (void)clear {
  self.storageDictionary = [NSDictionary new];
}

- (void)removeObjectForKey:(NSString *)key {
  NSMutableDictionary *tempDictionary = [self.storageDictionary mutableCopy];
  [tempDictionary removeObjectForKey:key];
  self.storageDictionary = [tempDictionary copy];
}

@end
