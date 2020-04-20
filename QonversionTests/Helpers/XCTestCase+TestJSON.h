#import <XCTest/XCTest.h>

@interface XCTestCase (TestJSON)

- (id)JSONObjectFromContentsOfFile:(NSString *)filePath;
- (id)fileDataFromContentsOfFile:(NSString *)filePath;
- (id)JSONObjectFromData:(NSData *)data;

@end
