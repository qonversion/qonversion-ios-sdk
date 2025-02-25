#import "QNLocalStorage.h"

@interface QNInMemoryStorage : NSObject <QNLocalStorage>

+ (instancetype)sharedInstance;

@property (atomic, copy) NSDictionary *storageDictionary;

@end
