#import <Foundation/Foundation.h>
#import "QLocalStorage.h"

@interface QUserDefaultsStorage : NSObject <QLocalStorage>

@property (nonatomic, strong) NSUserDefaults *userDefaults;

@end
