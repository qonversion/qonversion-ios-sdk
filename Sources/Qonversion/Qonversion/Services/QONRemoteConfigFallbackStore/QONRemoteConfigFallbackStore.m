//
//  QONRemoteConfigFallbackStore.m
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigFallbackStore.h"
#import "QONRemoteConfigJSON.h"
#import "QONRemoteConfigV2Models.h"

#import <CommonCrypto/CommonDigest.h>

static NSString *const kQONRemoteConfigDefaultsResourceName = @"qonversion_remote_config_defaults";
static NSString *const kQONRemoteConfigDefaultsResourceExtension = @"json";

static NSUInteger const kQONRemoteConfigDefaultsMaxArtifactBytes = 8 * 1024 * 1024;
static NSUInteger const kQONRemoteConfigDefaultsMaxCount = 1000;
static NSUInteger const kQONRemoteConfigDefaultsMaxValueBytes = 64 * 1024;
static NSUInteger const kQONRemoteConfigDefaultsMaxKeyBytes = 256;
static NSUInteger const kQONRemoteConfigDefaultsMaxUIDCodePoints = 36;
static NSUInteger const kQONRemoteConfigDefaultsMaxJSONDepth = 64;
static int64_t const kQONRemoteConfigDefaultsMaxSafeInteger = 9007199254740991LL;
static NSInteger const kQONRemoteConfigDefaultsSchemaVersion = 1;

// This exact domain is shared by every SDK and the producer. Changing it is a
// wire-format change and requires a new artifact schema.
static const char kQONRemoteConfigDefaultsDigestDomain[] =
    "qonversion.remote-config-fallback-defaults.v1";

typedef struct {
  const uint8_t *bytes;
  NSUInteger length;
  NSUInteger offset;
} QONRemoteConfigJSONScanner;

static BOOL QONRemoteConfigIsJSONWhitespace(uint8_t byte) {
  return byte == ' ' || byte == '\t' || byte == '\n' || byte == '\r';
}

static void QONRemoteConfigSkipJSONWhitespace(QONRemoteConfigJSONScanner *scanner) {
  while (scanner->offset < scanner->length &&
         QONRemoteConfigIsJSONWhitespace(scanner->bytes[scanner->offset])) {
    scanner->offset += 1;
  }
}

static BOOL QONRemoteConfigDecodeJSONCodeUnit(const uint8_t *bytes, uint16_t *result) {
  uint16_t value = 0;
  for (NSUInteger index = 0; index < 4; index++) {
    uint8_t byte = bytes[index];
    value <<= 4;
    if (byte >= '0' && byte <= '9') {
      value |= (uint16_t)(byte - '0');
    } else if (byte >= 'a' && byte <= 'f') {
      value |= (uint16_t)(byte - 'a' + 10);
    } else if (byte >= 'A' && byte <= 'F') {
      value |= (uint16_t)(byte - 'A' + 10);
    } else {
      return NO;
    }
  }
  if (result) {
    *result = value;
  }
  return YES;
}

static BOOL QONRemoteConfigScanJSONString(QONRemoteConfigJSONScanner *scanner,
                                          NSRange *range) {
  if (scanner->offset >= scanner->length || scanner->bytes[scanner->offset] != '"') {
    return NO;
  }

  NSUInteger start = scanner->offset;
  scanner->offset += 1;
  while (scanner->offset < scanner->length) {
    uint8_t byte = scanner->bytes[scanner->offset++];
    if (byte == '"') {
      if (range) {
        *range = NSMakeRange(start, scanner->offset - start);
      }
      return YES;
    }
    if (byte < 0x20) {
      return NO;
    }
    if (byte != '\\') {
      continue;
    }
    if (scanner->offset >= scanner->length) {
      return NO;
    }
    uint8_t escape = scanner->bytes[scanner->offset++];
    if (escape == 'u') {
      if (scanner->length - scanner->offset < 4) {
        return NO;
      }
      uint16_t codeUnit = 0;
      if (!QONRemoteConfigDecodeJSONCodeUnit(scanner->bytes + scanner->offset, &codeUnit)) {
        return NO;
      }
      scanner->offset += 4;
      if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
        if (scanner->length - scanner->offset < 6 ||
            scanner->bytes[scanner->offset] != '\\' ||
            scanner->bytes[scanner->offset + 1] != 'u') {
          return NO;
        }
        uint16_t lowSurrogate = 0;
        if (!QONRemoteConfigDecodeJSONCodeUnit(scanner->bytes + scanner->offset + 2,
                                               &lowSurrogate) ||
            lowSurrogate < 0xDC00 || lowSurrogate > 0xDFFF) {
          return NO;
        }
        scanner->offset += 6;
      } else if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
        return NO;
      }
    } else if (!(escape == '"' || escape == '\\' || escape == '/' ||
                 escape == 'b' || escape == 'f' || escape == 'n' ||
                 escape == 'r' || escape == 't')) {
      return NO;
    }
  }
  return NO;
}

static BOOL QONRemoteConfigScanJSONValue(QONRemoteConfigJSONScanner *scanner,
                                         NSUInteger depth);

static NSString *QONRemoteConfigDecodedJSONString(QONRemoteConfigJSONScanner *scanner,
                                                   NSRange range) {
  NSData *data = [NSData dataWithBytes:scanner->bytes + range.location length:range.length];
  id value = [NSJSONSerialization JSONObjectWithData:data
                                             options:NSJSONReadingFragmentsAllowed
                                               error:nil];
  return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL QONRemoteConfigScanJSONObject(QONRemoteConfigJSONScanner *scanner,
                                          NSUInteger depth) {
  if (depth >= kQONRemoteConfigDefaultsMaxJSONDepth) {
    return NO;
  }
  scanner->offset += 1;
  QONRemoteConfigSkipJSONWhitespace(scanner);
  if (scanner->offset < scanner->length && scanner->bytes[scanner->offset] == '}') {
    scanner->offset += 1;
    return YES;
  }

  NSMutableSet<NSString *> *keys = [NSMutableSet new];
  while (scanner->offset < scanner->length) {
    NSRange keyRange = NSMakeRange(NSNotFound, 0);
    if (!QONRemoteConfigScanJSONString(scanner, &keyRange)) {
      return NO;
    }
    NSString *key = QONRemoteConfigDecodedJSONString(scanner, keyRange);
    if (!key || [keys containsObject:key]) {
      return NO;
    }
    [keys addObject:key];

    QONRemoteConfigSkipJSONWhitespace(scanner);
    if (scanner->offset >= scanner->length || scanner->bytes[scanner->offset++] != ':') {
      return NO;
    }
    if (!QONRemoteConfigScanJSONValue(scanner, depth + 1)) {
      return NO;
    }
    QONRemoteConfigSkipJSONWhitespace(scanner);
    if (scanner->offset >= scanner->length) {
      return NO;
    }
    uint8_t delimiter = scanner->bytes[scanner->offset++];
    if (delimiter == '}') {
      return YES;
    }
    if (delimiter != ',') {
      return NO;
    }
    QONRemoteConfigSkipJSONWhitespace(scanner);
  }
  return NO;
}

static BOOL QONRemoteConfigScanJSONArray(QONRemoteConfigJSONScanner *scanner,
                                         NSUInteger depth) {
  if (depth >= kQONRemoteConfigDefaultsMaxJSONDepth) {
    return NO;
  }
  scanner->offset += 1;
  QONRemoteConfigSkipJSONWhitespace(scanner);
  if (scanner->offset < scanner->length && scanner->bytes[scanner->offset] == ']') {
    scanner->offset += 1;
    return YES;
  }

  while (scanner->offset < scanner->length) {
    if (!QONRemoteConfigScanJSONValue(scanner, depth + 1)) {
      return NO;
    }
    QONRemoteConfigSkipJSONWhitespace(scanner);
    if (scanner->offset >= scanner->length) {
      return NO;
    }
    uint8_t delimiter = scanner->bytes[scanner->offset++];
    if (delimiter == ']') {
      return YES;
    }
    if (delimiter != ',') {
      return NO;
    }
    QONRemoteConfigSkipJSONWhitespace(scanner);
  }
  return NO;
}

static BOOL QONRemoteConfigScanJSONNumber(QONRemoteConfigJSONScanner *scanner) {
  NSUInteger offset = scanner->offset;
  if (offset < scanner->length && scanner->bytes[offset] == '-') {
    offset += 1;
  }
  NSUInteger integerStart = offset;
  if (offset >= scanner->length) {
    return NO;
  }
  if (scanner->bytes[offset] == '0') {
    offset += 1;
  } else if (scanner->bytes[offset] >= '1' && scanner->bytes[offset] <= '9') {
    do {
      offset += 1;
    } while (offset < scanner->length &&
             scanner->bytes[offset] >= '0' && scanner->bytes[offset] <= '9');
  } else {
    return NO;
  }
  BOOL hasFractionOrExponent = NO;
  if (offset < scanner->length && scanner->bytes[offset] == '.') {
    hasFractionOrExponent = YES;
    offset += 1;
    NSUInteger fractionStart = offset;
    while (offset < scanner->length &&
           scanner->bytes[offset] >= '0' && scanner->bytes[offset] <= '9') {
      offset += 1;
    }
    if (offset == fractionStart) {
      return NO;
    }
  }
  if (offset < scanner->length &&
      (scanner->bytes[offset] == 'e' || scanner->bytes[offset] == 'E')) {
    hasFractionOrExponent = YES;
    offset += 1;
    if (offset < scanner->length &&
        (scanner->bytes[offset] == '+' || scanner->bytes[offset] == '-')) {
      offset += 1;
    }
    NSUInteger exponentStart = offset;
    while (offset < scanner->length &&
           scanner->bytes[offset] >= '0' && scanner->bytes[offset] <= '9') {
      offset += 1;
    }
    if (offset == exponentStart) {
      return NO;
    }
  }
  if (!hasFractionOrExponent) {
    static const char kMaxSafeInteger[] = "9007199254740991";
    NSUInteger digitCount = offset - integerStart;
    NSUInteger maxDigitCount = strlen(kMaxSafeInteger);
    if (digitCount > maxDigitCount ||
        (digitCount == maxDigitCount &&
         memcmp(scanner->bytes + integerStart, kMaxSafeInteger, maxDigitCount) > 0)) {
      return NO;
    }
  }
  scanner->offset = offset;
  return YES;
}

static BOOL QONRemoteConfigScanJSONLiteral(QONRemoteConfigJSONScanner *scanner,
                                           const char *literal) {
  NSUInteger length = strlen(literal);
  if (scanner->length - scanner->offset < length ||
      memcmp(scanner->bytes + scanner->offset, literal, length) != 0) {
    return NO;
  }
  scanner->offset += length;
  return YES;
}

static BOOL QONRemoteConfigScanJSONValue(QONRemoteConfigJSONScanner *scanner,
                                         NSUInteger depth) {
  QONRemoteConfigSkipJSONWhitespace(scanner);
  if (scanner->offset >= scanner->length) {
    return NO;
  }
  switch (scanner->bytes[scanner->offset]) {
    case '{':
      return QONRemoteConfigScanJSONObject(scanner, depth);
    case '[':
      return QONRemoteConfigScanJSONArray(scanner, depth);
    case '"':
      return QONRemoteConfigScanJSONString(scanner, NULL);
    case 't':
      return QONRemoteConfigScanJSONLiteral(scanner, "true");
    case 'f':
      return QONRemoteConfigScanJSONLiteral(scanner, "false");
    case 'n':
      return QONRemoteConfigScanJSONLiteral(scanner, "null");
    default:
      return QONRemoteConfigScanJSONNumber(scanner);
  }
}

BOOL QONRemoteConfigIsPortableJSONData(NSData *data, NSUInteger maxBytes) {
  if (data.length == 0 || data.length > maxBytes ||
      ![[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]) {
    return NO;
  }

  QONRemoteConfigJSONScanner scanner = {
    .bytes = data.bytes,
    .length = data.length,
    .offset = 0,
  };
  if (!QONRemoteConfigScanJSONValue(&scanner, 0)) {
    return NO;
  }
  QONRemoteConfigSkipJSONWhitespace(&scanner);
  return scanner.offset == scanner.length;
}

id QONRemoteConfigPortableJSONObject(NSData *data, NSUInteger maximumBytes) {
  if (!QONRemoteConfigIsPortableJSONData(data, maximumBytes)) {
    return nil;
  }

  return [NSJSONSerialization JSONObjectWithData:data
                                         options:NSJSONReadingFragmentsAllowed
                                           error:nil];
}

static BOOL QONRemoteConfigIsIntegralNumber(id value) {
  return [value isKindOfClass:NSNumber.class] &&
      CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
      !CFNumberIsFloatType((__bridge CFNumberRef)value);
}

static BOOL QONRemoteConfigIsPositiveInt64(id value, int64_t *result) {
  if (!QONRemoteConfigIsIntegralNumber(value)) {
    return NO;
  }
  NSNumber *number = value;
  int64_t candidate = number.longLongValue;
  if (candidate <= 0 || candidate > kQONRemoteConfigDefaultsMaxSafeInteger ||
      ![number isEqualToNumber:@(candidate)]) {
    return NO;
  }
  if (result) {
    *result = candidate;
  }
  return YES;
}

static NSUInteger QONRemoteConfigUTF8CodePointCount(NSData *data) {
  NSUInteger count = 0;
  const uint8_t *bytes = data.bytes;
  for (NSUInteger index = 0; index < data.length; index++) {
    if ((bytes[index] & 0xC0) != 0x80) {
      count += 1;
    }
  }
  return count;
}

static NSData *QONRemoteConfigValidatedUIDData(id value) {
  if (![value isKindOfClass:NSString.class]) {
    return nil;
  }
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger count = QONRemoteConfigUTF8CodePointCount(data);
  return data.length > 0 && count <= kQONRemoteConfigDefaultsMaxUIDCodePoints ? data : nil;
}

static NSData *QONRemoteConfigValidatedKeyData(id value) {
  if (![value isKindOfClass:NSString.class]) {
    return nil;
  }
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  return data.length > 0 && data.length <= kQONRemoteConfigDefaultsMaxKeyBytes ? data : nil;
}

static NSComparisonResult QONRemoteConfigCompareBytes(NSData *left, NSData *right) {
  NSUInteger commonLength = MIN(left.length, right.length);
  int comparison = memcmp(left.bytes, right.bytes, commonLength);
  if (comparison < 0) return NSOrderedAscending;
  if (comparison > 0) return NSOrderedDescending;
  if (left.length < right.length) return NSOrderedAscending;
  if (left.length > right.length) return NSOrderedDescending;
  return NSOrderedSame;
}

static NSData *QONRemoteConfigDecodeLowercaseSHA256Hex(id value) {
  if (![value isKindOfClass:NSString.class]) {
    return nil;
  }
  NSString *string = value;
  if (string.length != CC_SHA256_DIGEST_LENGTH * 2 ||
      ![string isEqualToString:string.lowercaseString]) {
    return nil;
  }
  NSMutableData *data = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
  uint8_t *bytes = data.mutableBytes;
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    unichar high = [string characterAtIndex:index * 2];
    unichar low = [string characterAtIndex:index * 2 + 1];
    int highValue = high >= '0' && high <= '9' ? high - '0' :
        (high >= 'a' && high <= 'f' ? high - 'a' + 10 : -1);
    int lowValue = low >= '0' && low <= '9' ? low - '0' :
        (low >= 'a' && low <= 'f' ? low - 'a' + 10 : -1);
    if (highValue < 0 || lowValue < 0) {
      return nil;
    }
    bytes[index] = (uint8_t)((highValue << 4) | lowValue);
  }
  return data;
}

static void QONRemoteConfigAppendASCII(NSMutableData *data, NSString *string) {
  NSData *bytes = [string dataUsingEncoding:NSASCIIStringEncoding];
  [data appendData:bytes];
}

static void QONRemoteConfigAppendJSONString(NSMutableData *data, NSString *string) {
  QONRemoteConfigAppendASCII(data, @"\"");
  NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
  const uint8_t *bytes = utf8.bytes;
  NSUInteger scalarStart = 0;
  for (NSUInteger index = 0; index < utf8.length;) {
    uint8_t byte = bytes[index];
    NSUInteger scalarLength = byte < 0x80 ? 1 :
        ((byte & 0xE0) == 0xC0 ? 2 : ((byte & 0xF0) == 0xE0 ? 3 : 4));
    NSString *escape = nil;
    if (scalarLength == 1) {
      switch (byte) {
        case '"': escape = @"\\\""; break;
        case '\\': escape = @"\\\\"; break;
        case '\b': escape = @"\\b"; break;
        case '\f': escape = @"\\f"; break;
        case '\n': escape = @"\\n"; break;
        case '\r': escape = @"\\r"; break;
        case '\t': escape = @"\\t"; break;
        case '<': escape = @"\\u003c"; break;
        case '>': escape = @"\\u003e"; break;
        case '&': escape = @"\\u0026"; break;
        default:
          if (byte < 0x20) {
            escape = [NSString stringWithFormat:@"\\u%04x", byte];
          }
          break;
      }
    } else if (scalarLength == 3 && index + 2 < utf8.length &&
               ((bytes[index] == 0xE2 && bytes[index + 1] == 0x80 && bytes[index + 2] == 0xA8) ||
                (bytes[index] == 0xE2 && bytes[index + 1] == 0x80 && bytes[index + 2] == 0xA9))) {
      escape = bytes[index + 2] == 0xA8 ? @"\\u2028" : @"\\u2029";
    }
    if (escape) {
      if (index > scalarStart) {
        [data appendBytes:bytes + scalarStart length:index - scalarStart];
      }
      QONRemoteConfigAppendASCII(data, escape);
      scalarStart = index + scalarLength;
    }
    index += scalarLength;
  }
  if (scalarStart < utf8.length) {
    [data appendBytes:bytes + scalarStart length:utf8.length - scalarStart];
  }
  QONRemoteConfigAppendASCII(data, @"\"");
}

static NSData *QONRemoteConfigCanonicalArtifactData(NSDictionary *root,
                                                     NSArray<NSDictionary *> *defaults,
                                                     int64_t projectID,
                                                     int64_t releaseNumber) {
  NSMutableData *data = [NSMutableData new];
  QONRemoteConfigAppendASCII(data, @"{\"schemaVersion\":1,\"projectId\":");
  QONRemoteConfigAppendASCII(data, [NSString stringWithFormat:@"%lld", (long long)projectID]);
  QONRemoteConfigAppendASCII(data, @",\"environmentUid\":");
  QONRemoteConfigAppendJSONString(data, root[@"environmentUid"]);
  QONRemoteConfigAppendASCII(data, @",\"releaseUid\":");
  QONRemoteConfigAppendJSONString(data, root[@"releaseUid"]);
  QONRemoteConfigAppendASCII(data, @",\"releaseNumber\":");
  QONRemoteConfigAppendASCII(data, [NSString stringWithFormat:@"%lld", (long long)releaseNumber]);
  QONRemoteConfigAppendASCII(data, @",\"manifestContentHash\":");
  QONRemoteConfigAppendJSONString(data, root[@"manifestContentHash"]);
  QONRemoteConfigAppendASCII(data, @",\"defaultsDigest\":");
  QONRemoteConfigAppendJSONString(data, root[@"defaultsDigest"]);
  QONRemoteConfigAppendASCII(data, @",\"defaults\":[");
  for (NSUInteger index = 0; index < defaults.count; index++) {
    if (index > 0) {
      QONRemoteConfigAppendASCII(data, @",");
    }
    NSDictionary *entry = defaults[index];
    QONRemoteConfigAppendASCII(data, @"{\"key\":");
    QONRemoteConfigAppendJSONString(data, entry[@"key"]);
    QONRemoteConfigAppendASCII(data, @",\"variationUid\":");
    QONRemoteConfigAppendJSONString(data, entry[@"variationUid"]);
    QONRemoteConfigAppendASCII(data, @",\"valueBase64\":");
    QONRemoteConfigAppendJSONString(data, entry[@"valueBase64"]);
    QONRemoteConfigAppendASCII(data, @"}");
  }
  QONRemoteConfigAppendASCII(data, @"]}");
  return data;
}

static void QONRemoteConfigDigestPart(CC_SHA256_CTX *context, NSData *part) {
  uint64_t length = CFSwapInt64HostToBig((uint64_t)part.length);
  CC_SHA256_Update(context, &length, (CC_LONG)sizeof(length));
  if (part.length > 0) {
    CC_SHA256_Update(context, part.bytes, (CC_LONG)part.length);
  }
}

static NSData *QONRemoteConfigASCIIData(NSString *string) {
  return [string dataUsingEncoding:NSASCIIStringEncoding];
}

static NSString *QONRemoteConfigDefaultsDigest(int64_t projectID,
                                                NSData *environmentUID,
                                                NSData *releaseUID,
                                                int64_t releaseNumber,
                                                NSData *manifestContentHash,
                                                NSArray<NSDictionary *> *defaults,
                                                NSArray<NSData *> *keys,
                                                NSArray<NSData *> *variationUIDs,
                                                NSArray<NSData *> *rawValues) {
  CC_SHA256_CTX context;
  CC_SHA256_Init(&context);
  QONRemoteConfigDigestPart(&context,
      [NSData dataWithBytes:kQONRemoteConfigDefaultsDigestDomain
                     length:strlen(kQONRemoteConfigDefaultsDigestDomain)]);
  QONRemoteConfigDigestPart(&context, QONRemoteConfigASCIIData(@"1"));
  QONRemoteConfigDigestPart(&context,
      QONRemoteConfigASCIIData([NSString stringWithFormat:@"%lld", (long long)projectID]));
  QONRemoteConfigDigestPart(&context, environmentUID);
  QONRemoteConfigDigestPart(&context, releaseUID);
  QONRemoteConfigDigestPart(&context,
      QONRemoteConfigASCIIData([NSString stringWithFormat:@"%lld", (long long)releaseNumber]));
  QONRemoteConfigDigestPart(&context, manifestContentHash);
  QONRemoteConfigDigestPart(&context,
      QONRemoteConfigASCIIData([NSString stringWithFormat:@"%lu", (unsigned long)defaults.count]));
  for (NSUInteger index = 0; index < defaults.count; index++) {
    QONRemoteConfigDigestPart(&context, keys[index]);
    QONRemoteConfigDigestPart(&context, variationUIDs[index]);
    QONRemoteConfigDigestPart(&context, rawValues[index]);
  }
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(digest, &context);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return hex;
}

@interface QONRemoteConfigFallbackStore ()

@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *values;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSData *> *rawValues;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *variationUIDs;
@property (nonatomic, assign) int64_t loadedProjectID;
@property (nonatomic, copy, nullable) NSString *loadedEnvironmentUID;
@property (nonatomic, copy, nullable) NSString *loadedReleaseUID;
@property (nonatomic, assign) int64_t loadedReleaseNumber;
@property (nonatomic, copy, nullable) NSString *loadedManifestContentHash;
@property (nonatomic, assign) BOOL didLoad;

@end

@implementation QONRemoteConfigFallbackStore

- (instancetype)initWithBundle:(NSBundle *)bundle {
  self = [super init];
  if (self) {
    _bundle = bundle;
  }
  return self;
}

- (void)ensureLoaded {
  @synchronized (self) {
    if (!self.didLoad) {
      self.values = [self loadValidatedValues];
      self.didLoad = YES;
    }
  }
}

- (id)valueForContextKey:(NSString *)contextKey {
  if (!contextKey) return nil;
  [self ensureLoaded];
  @synchronized (self) {
    return self.values[contextKey];
  }
}

- (NSData *)rawValueForContextKey:(NSString *)contextKey {
  if (!contextKey) return nil;
  [self ensureLoaded];
  @synchronized (self) { return [self.rawValues[contextKey] copy]; }
}

- (int64_t)projectID { [self ensureLoaded]; return self.loadedProjectID; }
- (NSString *)environmentUID { [self ensureLoaded]; return [self.loadedEnvironmentUID copy]; }

- (QONRemoteConfigV2Release *)remoteConfigV2FallbackRelease {
  [self ensureLoaded];
  @synchronized (self) {
    if (!self.values || !self.loadedReleaseUID || !self.loadedManifestContentHash) return nil;
    NSMutableDictionary *entries = [NSMutableDictionary dictionaryWithCapacity:self.rawValues.count];
    for (NSString *key in self.rawValues) {
      NSData *rawData = self.rawValues[key];
      NSString *variationUID = self.variationUIDs[key];
      if (!rawData || !variationUID) return nil;
      QONRemoteConfigV2Entry *entry = [[QONRemoteConfigV2Entry alloc]
          initWithKey:key rawData:rawData variationUID:variationUID
          applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
      if (!entry) return nil;
      entries[key] = entry;
    }
    NSString *releaseUID = self.loadedReleaseUID;
    NSString *manifestContentHash = self.loadedManifestContentHash;
    if (!releaseUID || !manifestContentHash) return nil;
    return [[QONRemoteConfigV2Release alloc] initWithReleaseUID:releaseUID
        releaseNumber:(NSInteger)self.loadedReleaseNumber
        manifestContentHash:manifestContentHash entries:entries];
  }
}

- (NSDictionary<NSString *, id> *)loadValidatedValues {
  NSURL *url = [self.bundle URLForResource:kQONRemoteConfigDefaultsResourceName
                             withExtension:kQONRemoteConfigDefaultsResourceExtension];
  if (!url) {
    return nil;
  }

  NSNumber *fileSize = nil;
  if (![url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil] ||
      fileSize.unsignedLongLongValue == 0 ||
      fileSize.unsignedLongLongValue > kQONRemoteConfigDefaultsMaxArtifactBytes) {
    return nil;
  }
  NSData *encoded = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
  if (encoded.length == 0 || encoded.length > kQONRemoteConfigDefaultsMaxArtifactBytes ||
      !QONRemoteConfigIsPortableJSONData(encoded, kQONRemoteConfigDefaultsMaxArtifactBytes)) {
    return nil;
  }

  id rootObject = [NSJSONSerialization JSONObjectWithData:encoded options:0 error:nil];
  if (![rootObject isKindOfClass:NSDictionary.class]) {
    return nil;
  }
  NSDictionary *root = rootObject;

  if (!QONRemoteConfigIsIntegralNumber(root[@"schemaVersion"]) ||
      [root[@"schemaVersion"] longLongValue] != kQONRemoteConfigDefaultsSchemaVersion) {
    return nil;
  }
  int64_t projectID = 0;
  int64_t releaseNumber = 0;
  if (!QONRemoteConfigIsPositiveInt64(root[@"projectId"], &projectID) ||
      !QONRemoteConfigIsPositiveInt64(root[@"releaseNumber"], &releaseNumber)) {
    return nil;
  }
  NSData *environmentUID = QONRemoteConfigValidatedUIDData(root[@"environmentUid"]);
  NSData *releaseUID = QONRemoteConfigValidatedUIDData(root[@"releaseUid"]);
  NSData *decodedManifestContentHash = QONRemoteConfigDecodeLowercaseSHA256Hex(root[@"manifestContentHash"]);
  NSData *manifestContentHash = [root[@"manifestContentHash"] dataUsingEncoding:NSASCIIStringEncoding];
  if (!environmentUID || !releaseUID || !decodedManifestContentHash ||
      !QONRemoteConfigDecodeLowercaseSHA256Hex(root[@"defaultsDigest"])) {
    return nil;
  }

  id defaultsObject = root[@"defaults"];
  if (![defaultsObject isKindOfClass:NSArray.class] ||
      [defaultsObject count] > kQONRemoteConfigDefaultsMaxCount) {
    return nil;
  }
  NSArray *defaults = defaultsObject;
  NSMutableArray<NSData *> *keys = [NSMutableArray arrayWithCapacity:defaults.count];
  NSMutableArray<NSData *> *variationUIDs = [NSMutableArray arrayWithCapacity:defaults.count];
  NSMutableArray<NSData *> *rawValues = [NSMutableArray arrayWithCapacity:defaults.count];
  NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionaryWithCapacity:defaults.count];
  NSMutableDictionary<NSString *, NSData *> *rawValuesByKey = [NSMutableDictionary dictionaryWithCapacity:defaults.count];
  NSMutableDictionary<NSString *, NSString *> *variationUIDsByKey = [NSMutableDictionary dictionaryWithCapacity:defaults.count];
  NSData *previousKey = nil;

  for (id entryObject in defaults) {
    if (![entryObject isKindOfClass:NSDictionary.class]) {
      return nil;
    }
    NSDictionary *entry = entryObject;
    id keyObject = entry[@"key"];
    id variationUIDObject = entry[@"variationUid"];
    NSData *key = QONRemoteConfigValidatedKeyData(keyObject);
    NSData *variationUID = QONRemoteConfigValidatedUIDData(variationUIDObject);
    id base64Object = entry[@"valueBase64"];
    if (!key || !variationUID || ![base64Object isKindOfClass:NSString.class] ||
        (previousKey && QONRemoteConfigCompareBytes(previousKey, key) != NSOrderedAscending)) {
      return nil;
    }
    NSString *base64 = base64Object;
    NSData *rawValue = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!rawValue || rawValue.length == 0 || rawValue.length > kQONRemoteConfigDefaultsMaxValueBytes ||
        ![[rawValue base64EncodedStringWithOptions:0] isEqualToString:base64]) {
      return nil;
    }
    id value = QONRemoteConfigPortableJSONObject(rawValue, kQONRemoteConfigDefaultsMaxValueBytes);
    if (!value) {
      return nil;
    }
    NSString *entryKey = (NSString *)keyObject;
    NSString *entryVariationUID = (NSString *)variationUIDObject;

    [keys addObject:key];
    [variationUIDs addObject:variationUID];
    [rawValues addObject:rawValue];
    values[entryKey] = value;
    rawValuesByKey[entryKey] = rawValue;
    variationUIDsByKey[entryKey] = entryVariationUID;
    previousKey = key;
  }

  NSString *digest = QONRemoteConfigDefaultsDigest(projectID, environmentUID, releaseUID,
      releaseNumber, manifestContentHash, defaults, keys, variationUIDs, rawValues);
  NSString *expectedDigest = root[@"defaultsDigest"];
  if (![expectedDigest isKindOfClass:NSString.class] || ![digest isEqualToString:expectedDigest]) {
    return nil;
  }

  NSData *canonical = QONRemoteConfigCanonicalArtifactData(root, defaults, projectID, releaseNumber);
  if (![canonical isEqualToData:encoded]) {
    return nil;
  }
  self.rawValues = [rawValuesByKey copy];
  self.variationUIDs = [variationUIDsByKey copy];
  self.loadedProjectID = projectID;
  self.loadedEnvironmentUID = root[@"environmentUid"];
  self.loadedReleaseUID = root[@"releaseUid"];
  self.loadedReleaseNumber = releaseNumber;
  self.loadedManifestContentHash = root[@"manifestContentHash"];
  return [values copy];
}

@end
