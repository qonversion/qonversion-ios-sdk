#import <XCTest/XCTest.h>

@interface XCTestCase (IntegrationTestJSON)

- (NSDictionary *)dictionaryFromContentsOfFile:(NSString *)filePath;
- (id)fileDataFromContentsOfFile:(NSString *)filePath;
- (id)JSONObjectFromContentsOfFile:(NSString *)filePath;

@end
