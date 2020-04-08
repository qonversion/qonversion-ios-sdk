#import "XCTestCase+TestJSON.h"

@implementation XCTestCase (TestJSON)

- (id)JSONObjectFromContentsOfFile:(NSString *)filePath {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    
    NSString *fileName = [filePath stringByDeletingPathExtension];
    NSString *fileExtension = [filePath pathExtension];
    NSString *pathToFile = [bundle pathForResource:fileName ofType:fileExtension];
    
    NSData *fileData = [NSData dataWithContentsOfFile:pathToFile];
    NSDictionary *object = [NSJSONSerialization JSONObjectWithData:fileData options:kNilOptions error:nil];
    return object;
}

@end
