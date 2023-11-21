#import <Foundation/Foundation.h>
#import "QNLocalStorage.h"

@interface QNUserDefaultsStorage : NSObject <QNLocalStorage>

@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, strong) NSUserDefaults *customUserDefaults;

@end
