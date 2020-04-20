#import "XCTestCase+TestJSON.h"

@implementation XCTestCase (TestJSON)

- (id)JSONObjectFromContentsOfFile:(NSString *)filePath {
    NSData *fileData = [self fileDataFromContentsOfFile:filePath];
    
    return [NSJSONSerialization JSONObjectWithData:fileData options:kNilOptions error:nil];
}

- (id)fileDataFromContentsOfFile:(NSString *)filePath {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    
    NSString *fileName = [filePath stringByDeletingPathExtension];
    NSString *fileExtension = [filePath pathExtension];
    NSString *pathToFile = [bundle pathForResource:fileName ofType:fileExtension];
    
    return [NSData dataWithContentsOfFile:pathToFile];
}

- (id)JSONObjectFromData:(NSData *)data {
    return [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
}

@end
