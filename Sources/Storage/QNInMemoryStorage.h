#import "QNLocalStorage.h"

@interface QNInMemoryStorage : NSObject <QNLocalStorage>

+ (instancetype)sharedInstance;

@property (nonatomic, strong) NSDictionary *storageDictionary;

@end
