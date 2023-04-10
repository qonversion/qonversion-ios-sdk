#import "XCTestCase+Helpers.h"

@implementation XCTestCase (Helpers)

- (BOOL)areArraysDeepEqual:(NSArray *)first second:(NSArray *)second {
  if (@available(iOS 13.0, *)) {
    NSOrderedCollectionDifference *diff = [first differenceFromArray:second
                                                         withOptions:0
                                                usingEquivalenceTest:^BOOL(id  _Nonnull obj1, id  _Nonnull obj2) {
      return [self areObjectsEqual:obj1 second:obj2];
    }];

    return ![diff hasChanges];
  } else {
    return [first isEqualToArray:second];
  }
}

- (BOOL)areDictionariesDeepEqual:(NSDictionary *)first second:(NSDictionary *)second {
  if (first.count != second.count) {
    return NO;
  }
  BOOL hasDiff = NO;
  for (NSString *key in first.allKeys) {
    id obj1 = first[key];
    id obj2 = second[key];

    hasDiff = ![self areObjectsEqual:obj1 second:obj2];

    if (hasDiff) {
      break;
    }
  }
  
  return !hasDiff;
}

- (BOOL)areObjectsEqual:(id  _Nonnull)obj1 second:(id  _Nonnull)obj2 {
  if ([obj1 isKindOfClass:[NSArray class]] && [obj2 isKindOfClass:[NSArray class]]) {
    return [self areArraysDeepEqual:obj1 second:obj2];
  }
  if ([obj1 isKindOfClass:[NSDictionary class]] && [obj2 isKindOfClass:[NSDictionary class]]) {
    return [self areDictionariesDeepEqual:obj1 second:obj2];
  }
  if ([obj1 isKindOfClass:[NSNumber class]] && [obj2 isKindOfClass:[NSNumber class]]) {
    return [obj1 isEqualToNumber:obj2];
  }
  if ([obj1 isKindOfClass:[NSString class]] && [obj2 isKindOfClass:[NSString class]]) {
    return [obj1 isEqualToString:obj2];
  }
  return obj1 == obj2;
}

@end
