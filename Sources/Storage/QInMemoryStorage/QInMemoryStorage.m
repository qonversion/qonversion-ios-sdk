#import "QInMemoryStorage.h"

static NSString *QInMemoryStorageDefaultKey = @"inMemoryStorageDefaultKey";

@interface QInMemoryStorage ()

@property (nonatomic, copy) NSString *version;

@end

@implementation QInMemoryStorage

+ (instancetype)sharedInstance {
    static QInMemoryStorage *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [QInMemoryStorage new];
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
    [self storeObject:object forKey:QInMemoryStorageDefaultKey];
}

- (void)storeObject:(id)object forKey:(NSString *)key {
    NSMutableDictionary *tempDictionary = [self.storageDictionary mutableCopy];
    [tempDictionary setValue:object forKey:key];
    self.storageDictionary = tempDictionary;
}

- (id)loadObject {
    return [self loadObjectForKey:QInMemoryStorageDefaultKey];
}

- (id)loadObjectForKey:(NSString *)key {
    return self.storageDictionary[key];
}

- (void)loadObjectWithCompletion:(void (^)(id))completion {
    [self loadObjectForKey:QInMemoryStorageDefaultKey
            withCompletion:completion];
}

- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
    id object = [self loadObjectForKey:key];
    run_block(completion, object);
}

- (void)removeObject {
    [self removeObjectForKey:QInMemoryStorageDefaultKey];
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
