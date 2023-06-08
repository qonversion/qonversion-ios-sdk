#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TestBlock)(NSInvocation *);

@interface XCTestCase (Helpers)

- (BOOL)areArraysDeepEqual:(NSArray *)first second:(NSArray *)second;
- (BOOL)areDictionariesDeepEqual:(NSDictionary *)first second:(NSDictionary *)second;
- (BOOL)areObjectsEqual:(id _Nonnull)obj1 second:(id _Nonnull)obj2;

@end

NS_ASSUME_NONNULL_END
