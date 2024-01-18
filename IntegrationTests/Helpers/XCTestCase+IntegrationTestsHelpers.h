#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TestBlock)(NSInvocation *);

@interface XCTestCase (IntegrationTestsHelpers)

- (BOOL)areArraysDeepEqual:(NSArray *)first second:(NSArray *)second;
- (BOOL)areArraysOfDictionariesEqual:(NSArray *)first second:(NSArray *)second descriptor:(NSString *)descriptor;
- (BOOL)areDictionariesDeepEqual:(NSDictionary *)first second:(NSDictionary *)second;
- (BOOL)areObjectsEqual:(id _Nonnull)obj1 second:(id _Nonnull)obj2;

@end

NS_ASSUME_NONNULL_END
