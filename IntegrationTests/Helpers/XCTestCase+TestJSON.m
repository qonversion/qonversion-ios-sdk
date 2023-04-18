#import "XCTestCase+TestJSON.h"

@implementation XCTestCase (TestJSON)

- (NSDictionary *)dictionaryFromContentsOfFile:(NSString *)filePath {
  NSData *fileData = [self fileDataFromContentsOfFile:filePath];
  
  NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:fileData options:kNilOptions error:nil];
  return jsonData;
}

- (id)fileDataFromContentsOfFile:(NSString *)filePath {
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  
  NSString *fileName = [filePath stringByDeletingPathExtension];
  NSString *fileExtension = [filePath pathExtension];
  NSString *pathToFile = [bundle pathForResource:fileName ofType:fileExtension];
  
  return [NSData dataWithContentsOfFile:pathToFile];
}

@end
