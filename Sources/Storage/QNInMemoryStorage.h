#import "QLocalStorage.h"

@interface QNInMemoryStorage : NSObject <QLocalStorage>

+ (instancetype)sharedInstance;

@property (nonatomic, strong) NSDictionary *storageDictionary;

@end
