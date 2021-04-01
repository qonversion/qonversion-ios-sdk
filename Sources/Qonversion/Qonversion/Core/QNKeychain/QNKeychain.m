#import "QNKeychain.h"
#import <Security/Security.h>

@implementation QNKeychain

- (void)setString:(NSString *)string forKey:(NSString *)key {
  if (!string || !key || ![string isKindOfClass:NSString.class] || ![key isKindOfClass:NSString.class]) {
    return;
  }
  NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
  NSData *valueData = [string dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
  
  NSDictionary *query = @{(id)kSecClass:(id)kSecClassGenericPassword,
                          (id)kSecAttrAccount:keyData,
                          (id)kSecValueData:valueData};
  
  SecItemDelete((__bridge CFDictionaryRef)query);
  SecItemAdd((__bridge CFDictionaryRef)query, nil);
}

- (nullable NSString *)stringForKey:(NSString *)key {
  NSData *data = [self valueForKey:key];
  if (!data) {
    return nil;
  }
  return [NSString.alloc initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)deleteValueForKey:(NSString *)key {
  NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
  NSDictionary *query = @{(id)kSecClass:(id)kSecClassGenericPassword,
                          (id)kSecAttrAccount:keyData};
  
  SecItemDelete((CFDictionaryRef)query);
}

// MARK: - Private

- (nullable NSData *)valueForKey:(NSString *)key; {
  NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
  if (!keyData) {
    return nil;
  }
  NSDictionary *query = @{(id)kSecClass:(id)kSecClassGenericPassword,
                          (id)kSecAttrAccount:keyData,
                          (id)kSecMatchLimit:(id)kSecMatchLimitOne,
                          (id)kSecReturnData:(id)kCFBooleanTrue};
  
  CFTypeRef typeRef = NULL;
  SecItemCopyMatching((__bridge CFDictionaryRef)query, &typeRef);
  return (__bridge NSData *)typeRef;
}

@end
