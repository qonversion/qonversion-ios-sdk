#import <XCTest/XCTest.h>

@interface XCTestCase (TestJSON)

- (NSDictionary *)dictionaryFromContentsOfFile:(NSString *)filePath;
- (id)fileDataFromContentsOfFile:(NSString *)filePath;

@end
