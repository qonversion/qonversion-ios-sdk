#import <XCTest/XCTest.h>

@interface XCTestCase (TestJSON)

- (id)JSONObjectFromContentsOfFile:(NSString *)filePath;

@end
