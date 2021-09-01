#import "QNInMemoryStorageInterface.h"

@interface QNInMemoryStorage : NSObject <QNInMemoryStorageInterface>

+ (instancetype)sharedInstance;

@property (nonatomic, strong) NSDictionary *storageDictionary;

@end
