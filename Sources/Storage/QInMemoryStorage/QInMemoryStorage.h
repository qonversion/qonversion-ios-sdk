#import "QLocalStorage.h"

@interface QInMemoryStorage : NSObject <QLocalStorage>

+ (instancetype)sharedInstance;

@property (nonatomic, strong) NSDictionary *storageDictionary;

@end
