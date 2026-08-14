#import "QONRemoteConfigV2Models.h"
#import "QONRemoteConfigJSON.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

NSUInteger const QONRemoteConfigV2MaximumEntryCount = 1000;
NSUInteger const QONRemoteConfigV2MaximumRawValueBytes = 64 * 1024;
NSUInteger const QONRemoteConfigV2MaximumMetadataBytes = 4 * 1024;
NSUInteger const QONRemoteConfigV2MaximumTotalValueBytes = 4 * 1024 * 1024;
NSUInteger const QONRemoteConfigV2MaximumKeyBytes = 256;
NSUInteger const QONRemoteConfigV2MaximumUIDCodePoints = 36;
NSUInteger const QONRemoteConfigV2MaximumScopeComponentBytes = 256;
NSUInteger const QONRemoteConfigV2MaximumEnvelopeBytes = 8 * 1024 * 1024;
int64_t const QONRemoteConfigV2MaximumSafeInteger = 9007199254740991LL;

static NSUInteger QONRemoteConfigV2CodePointCount(NSString *value) {
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger count = 0;
  const uint8_t *bytes = data.bytes;
  for (NSUInteger index = 0; index < data.length; index++) {
    if ((bytes[index] & 0xC0) != 0x80) count += 1;
  }
  return count;
}

static BOOL QONRemoteConfigV2ValidUID(NSString *value) {
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  return data.length > 0 &&
      QONRemoteConfigV2CodePointCount(value) <= QONRemoteConfigV2MaximumUIDCodePoints;
}

static BOOL QONRemoteConfigV2ValidBoundedString(NSString *value, NSUInteger maximumBytes) {
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  return data.length > 0 && data.length <= maximumBytes;
}

static BOOL QONRemoteConfigV2ValidSHA256(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 64 ||
      ![value isEqualToString:value.lowercaseString]) return NO;
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
  return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

BOOL QONRemoteConfigV2ValidContextFingerprint(NSString *value) {
  return QONRemoteConfigV2ValidSHA256(value);
}

static NSString *QONRemoteConfigV2SHA256Hex(NSData *data) {
  if (!data || data.length > UINT32_MAX) return nil;
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return [hex copy];
}

static BOOL QONRemoteConfigV2ValidStrongETag(NSString *eTag, NSData *body,
                                             NSString **bodyDigest) {
  if (eTag.length != 66 || ![eTag hasPrefix:@"\""] || ![eTag hasSuffix:@"\""]) return NO;
  NSString *digest = [eTag substringWithRange:NSMakeRange(1, 64)];
  if (!QONRemoteConfigV2ValidSHA256(digest) || ![digest isEqualToString:QONRemoteConfigV2SHA256Hex(body)]) {
    return NO;
  }
  if (bodyDigest) *bodyDigest = digest;
  return YES;
}

static id QONRemoteConfigV2DeepJSONCopy(id value) {
  if (!value) return nil;
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:value
                                                 options:NSJSONWritingFragmentsAllowed
                                                   error:&error];
  if (!data || error) return nil;
  return QONRemoteConfigPortableJSONObject(data, QONRemoteConfigV2MaximumMetadataBytes);
}

@implementation QONRemoteConfigV2Scope

- (instancetype)initWithProjectKey:(NSString *)projectKey
                        environment:(NSString *)environment
                    canonicalUserID:(NSString *)canonicalUserID {
  if (!QONRemoteConfigV2ValidBoundedString(projectKey, QONRemoteConfigV2MaximumScopeComponentBytes) ||
      !QONRemoteConfigV2ValidUID(environment) ||
      !QONRemoteConfigV2ValidBoundedString(canonicalUserID, QONRemoteConfigV2MaximumScopeComponentBytes)) return nil;
  self = [super init];
  if (self) {
    _projectKey = [projectKey copy];
    _environment = [environment copy];
    _canonicalUserID = [canonicalUserID copy];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSUInteger)hash { return self.projectKey.hash ^ self.environment.hash ^ self.canonicalUserID.hash; }
- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:QONRemoteConfigV2Scope.class]) return NO;
  QONRemoteConfigV2Scope *other = object;
  return [self.projectKey isEqualToString:other.projectKey] &&
      [self.environment isEqualToString:other.environment] &&
      [self.canonicalUserID isEqualToString:other.canonicalUserID];
}

@end

@implementation QONRemoteConfigV2EnvelopeExpectation

- (instancetype)initWithProjectID:(int64_t)projectID
                    environmentUID:(NSString *)environmentUID {
  return [self initWithProjectID:projectID environmentUID:environmentUID
              contextFingerprint:nil];
}

- (instancetype)initWithProjectID:(int64_t)projectID
                    environmentUID:(NSString *)environmentUID
                contextFingerprint:(NSString *)contextFingerprint {
  if (projectID <= 0 || projectID > QONRemoteConfigV2MaximumSafeInteger ||
      !QONRemoteConfigV2ValidUID(environmentUID) ||
      // nil means "any well-formed fingerprint"; a value must be a real one.
      (contextFingerprint != nil &&
       !QONRemoteConfigV2ValidContextFingerprint(contextFingerprint))) return nil;
  self = [super init];
  if (self) {
    _projectID = projectID;
    _environmentUID = [environmentUID copy];
    _contextFingerprint = [contextFingerprint copy];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }

@end

@interface QONRemoteConfigV2Envelope ()
@property (nonatomic, assign, readwrite) int64_t projectID;
@property (nonatomic, copy, readwrite) NSString *environmentUID;
@property (nonatomic, copy, readwrite) NSString *contextFingerprint;
@property (nonatomic, strong, readwrite) QONRemoteConfigV2Release *snapshotRelease;
@property (nonatomic, copy, readwrite) NSString *eTag;
@property (nonatomic, copy, readwrite) NSString *bodyDigest;
@property (nonatomic, copy, readwrite) NSData *canonicalBody;
@end

@implementation QONRemoteConfigV2Envelope
@end

typedef struct {
  const uint8_t *bytes;
  NSUInteger length;
  NSUInteger index;
  NSUInteger limit;
} QONRemoteConfigV2JSONReader;

static void QONRemoteConfigV2SkipWhitespace(QONRemoteConfigV2JSONReader *reader) {
  while (reader->index < reader->limit) {
    uint8_t byte = reader->bytes[reader->index];
    if (byte != ' ' && byte != '\t' && byte != '\r' && byte != '\n') break;
    reader->index += 1;
  }
}

static BOOL QONRemoteConfigV2Consume(QONRemoteConfigV2JSONReader *reader, uint8_t byte) {
  if (reader->index >= reader->limit || reader->bytes[reader->index] != byte) return NO;
  reader->index += 1;
  return YES;
}

static BOOL QONRemoteConfigV2Expect(QONRemoteConfigV2JSONReader *reader, uint8_t byte) {
  return QONRemoteConfigV2Consume(reader, byte);
}

static BOOL QONRemoteConfigV2IsHex(uint8_t byte) {
  return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f') ||
      (byte >= 'A' && byte <= 'F');
}

static NSString *QONRemoteConfigV2ReadString(QONRemoteConfigV2JSONReader *reader) {
  NSUInteger start = reader->index;
  if (!QONRemoteConfigV2Expect(reader, '"')) return nil;
  BOOL escaped = NO;
  while (reader->index < reader->limit) {
    uint8_t byte = reader->bytes[reader->index++];
    if (escaped) {
      if (byte == 'u') {
        for (NSUInteger count = 0; count < 4; count++) {
          if (reader->index >= reader->limit ||
              !QONRemoteConfigV2IsHex(reader->bytes[reader->index++])) return nil;
        }
      } else if (byte != '"' && byte != '\\' && byte != '/' && byte != 'b' &&
                 byte != 'f' && byte != 'n' && byte != 'r' && byte != 't') {
        return nil;
      }
      escaped = NO;
      continue;
    }
    if (byte == '\\') {
      escaped = YES;
    } else if (byte == '"') {
      NSData *quoted = [NSData dataWithBytes:reader->bytes + start
                                      length:reader->index - start];
      NSError *error = nil;
      id decoded = [NSJSONSerialization JSONObjectWithData:quoted
          options:NSJSONReadingFragmentsAllowed error:&error];
      if (error || ![decoded isKindOfClass:NSString.class]) return nil;
      NSData *utf8 = [decoded dataUsingEncoding:NSUTF8StringEncoding];
      return utf8 ? decoded : nil;
    } else if (byte < 0x20) {
      return nil;
    }
  }
  return nil;
}

static NSString *QONRemoteConfigV2ReadNumberToken(QONRemoteConfigV2JSONReader *reader) {
  NSUInteger start = reader->index;
  QONRemoteConfigV2Consume(reader, '-');
  if (QONRemoteConfigV2Consume(reader, '0')) {
    if (reader->index < reader->limit && reader->bytes[reader->index] >= '0' &&
        reader->bytes[reader->index] <= '9') return nil;
  } else {
    if (reader->index >= reader->limit || reader->bytes[reader->index] < '1' ||
        reader->bytes[reader->index] > '9') return nil;
    while (reader->index < reader->limit && reader->bytes[reader->index] >= '0' &&
           reader->bytes[reader->index] <= '9') reader->index += 1;
  }
  if (QONRemoteConfigV2Consume(reader, '.')) {
    if (reader->index >= reader->limit || reader->bytes[reader->index] < '0' ||
        reader->bytes[reader->index] > '9') return nil;
    while (reader->index < reader->limit && reader->bytes[reader->index] >= '0' &&
           reader->bytes[reader->index] <= '9') reader->index += 1;
  }
  if (reader->index < reader->limit &&
      (reader->bytes[reader->index] == 'e' || reader->bytes[reader->index] == 'E')) {
    reader->index += 1;
    if (reader->index < reader->limit &&
        (reader->bytes[reader->index] == '+' || reader->bytes[reader->index] == '-')) {
      reader->index += 1;
    }
    if (reader->index >= reader->limit || reader->bytes[reader->index] < '0' ||
        reader->bytes[reader->index] > '9') return nil;
    while (reader->index < reader->limit && reader->bytes[reader->index] >= '0' &&
           reader->bytes[reader->index] <= '9') reader->index += 1;
  }
  if (reader->index == start) return nil;
  return [[NSString alloc] initWithBytes:reader->bytes + start
      length:reader->index - start encoding:NSASCIIStringEncoding];
}

static BOOL QONRemoteConfigV2ValidatePortableNumber(NSString *token) {
  if (!token) return NO;
  if ([token rangeOfCharacterFromSet:
      [NSCharacterSet characterSetWithCharactersInString:@".eE"]].location == NSNotFound) {
    if (token.length > 17) return NO;
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:token
        locale:@{NSLocaleDecimalSeparator: @"."}];
    if ([number isEqual:NSDecimalNumber.notANumber]) return NO;
    NSDecimalNumber *maximum = [NSDecimalNumber decimalNumberWithMantissa:
        (uint64_t)QONRemoteConfigV2MaximumSafeInteger exponent:0 isNegative:NO];
    NSDecimalNumber *minimum = [maximum decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]];
    if ([number compare:minimum] == NSOrderedAscending || [number compare:maximum] == NSOrderedDescending) {
      return NO;
    }
  }
  NSData *tokenData = [token dataUsingEncoding:NSASCIIStringEncoding];
  if (!tokenData) return NO;
  NSError *error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:tokenData
      options:NSJSONReadingFragmentsAllowed error:&error];
  if (error || ![object isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)object) == CFBooleanGetTypeID()) return NO;
  return isfinite([(NSNumber *)object doubleValue]);
}

static BOOL QONRemoteConfigV2ScanPortableValue(QONRemoteConfigV2JSONReader *reader,
                                                NSUInteger depth);

static BOOL QONRemoteConfigV2ScanPortableObject(QONRemoteConfigV2JSONReader *reader,
                                                 NSUInteger depth) {
  if (depth > 64 || !QONRemoteConfigV2Expect(reader, '{')) return NO;
  QONRemoteConfigV2SkipWhitespace(reader);
  if (QONRemoteConfigV2Consume(reader, '}')) return YES;
  NSMutableSet<NSString *> *members = [NSMutableSet new];
  while (YES) {
    NSString *name = QONRemoteConfigV2ReadString(reader);
    if (!name || [members containsObject:name]) return NO;
    [members addObject:name];
    QONRemoteConfigV2SkipWhitespace(reader);
    if (!QONRemoteConfigV2Expect(reader, ':')) return NO;
    QONRemoteConfigV2SkipWhitespace(reader);
    if (!QONRemoteConfigV2ScanPortableValue(reader, depth + 1)) return NO;
    QONRemoteConfigV2SkipWhitespace(reader);
    if (QONRemoteConfigV2Consume(reader, '}')) return YES;
    if (!QONRemoteConfigV2Expect(reader, ',')) return NO;
    QONRemoteConfigV2SkipWhitespace(reader);
  }
}

static BOOL QONRemoteConfigV2ScanPortableArray(QONRemoteConfigV2JSONReader *reader,
                                                NSUInteger depth) {
  if (depth > 64 || !QONRemoteConfigV2Expect(reader, '[')) return NO;
  QONRemoteConfigV2SkipWhitespace(reader);
  if (QONRemoteConfigV2Consume(reader, ']')) return YES;
  while (YES) {
    if (!QONRemoteConfigV2ScanPortableValue(reader, depth + 1)) return NO;
    QONRemoteConfigV2SkipWhitespace(reader);
    if (QONRemoteConfigV2Consume(reader, ']')) return YES;
    if (!QONRemoteConfigV2Expect(reader, ',')) return NO;
    QONRemoteConfigV2SkipWhitespace(reader);
  }
}

static BOOL QONRemoteConfigV2ExpectLiteral(QONRemoteConfigV2JSONReader *reader,
                                            const char *literal) {
  for (const char *cursor = literal; *cursor; cursor++) {
    if (!QONRemoteConfigV2Expect(reader, (uint8_t)*cursor)) return NO;
  }
  return YES;
}

static BOOL QONRemoteConfigV2ScanPortableValue(QONRemoteConfigV2JSONReader *reader,
                                                NSUInteger depth) {
  if (reader->index >= reader->limit) return NO;
  switch (reader->bytes[reader->index]) {
    case '{': return QONRemoteConfigV2ScanPortableObject(reader, depth);
    case '[': return QONRemoteConfigV2ScanPortableArray(reader, depth);
    case '"': return QONRemoteConfigV2ReadString(reader) != nil;
    case 't': return QONRemoteConfigV2ExpectLiteral(reader, "true");
    case 'f': return QONRemoteConfigV2ExpectLiteral(reader, "false");
    case 'n': return QONRemoteConfigV2ExpectLiteral(reader, "null");
    default: return QONRemoteConfigV2ValidatePortableNumber(QONRemoteConfigV2ReadNumberToken(reader));
  }
}

static NSData *QONRemoteConfigV2ReadPortableSpan(QONRemoteConfigV2JSONReader *reader,
                                                 NSUInteger maximumBytes) {
  NSUInteger start = reader->index;
  NSUInteger outerLimit = reader->limit;
  NSUInteger valueLimit = MIN(outerLimit, start + maximumBytes);
  reader->limit = valueLimit;
  QONRemoteConfigV2SkipWhitespace(reader);
  BOOL valid = QONRemoteConfigV2ScanPortableValue(reader, 1);
  QONRemoteConfigV2SkipWhitespace(reader);
  NSUInteger end = reader->index;
  reader->limit = outerLimit;
  if (!valid || end <= start || end - start > maximumBytes) return nil;
  if (end == valueLimit && valueLimit < outerLimit) {
    uint8_t next = reader->bytes[end];
    if (next != ',' && next != '}' && next != ']') return nil;
  }
  return [NSData dataWithBytes:reader->bytes + start length:end - start];
}

static BOOL QONRemoteConfigV2ReadExactInteger(QONRemoteConfigV2JSONReader *reader,
                                               int64_t *value) {
  QONRemoteConfigV2SkipWhitespace(reader);
  NSString *token = QONRemoteConfigV2ReadNumberToken(reader);
  if (!token || [token rangeOfCharacterFromSet:
      [NSCharacterSet characterSetWithCharactersInString:@".eE"]].location != NSNotFound ||
      !QONRemoteConfigV2ValidatePortableNumber(token)) return NO;
  if (value) *value = token.longLongValue;
  return YES;
}

static NSString *QONRemoteConfigV2ReadStringValue(QONRemoteConfigV2JSONReader *reader) {
  QONRemoteConfigV2SkipWhitespace(reader);
  return QONRemoteConfigV2ReadString(reader);
}

static BOOL QONRemoteConfigV2ReadBooleanValue(QONRemoteConfigV2JSONReader *reader,
                                               BOOL *value) {
  QONRemoteConfigV2SkipWhitespace(reader);
  if (QONRemoteConfigV2ExpectLiteral(reader, "true")) {
    if (value) *value = YES;
    return YES;
  }
  if (QONRemoteConfigV2ExpectLiteral(reader, "false")) {
    if (value) *value = NO;
    return YES;
  }
  return NO;
}

static QONRemoteConfigV2Entry *QONRemoteConfigV2ReadWireEntry(
    QONRemoteConfigV2JSONReader *reader, NSString *key) {
  QONRemoteConfigV2SkipWhitespace(reader);
  if (!QONRemoteConfigV2Expect(reader, '{')) return nil;
  QONRemoteConfigV2SkipWhitespace(reader);
  if (QONRemoteConfigV2Consume(reader, '}')) return nil;
  NSMutableSet<NSString *> *members = [NSMutableSet new];
  NSData *raw = nil, *metadata = nil;
  NSString *variationUID = nil, *policyValue = nil;
  while (YES) {
    NSString *name = QONRemoteConfigV2ReadString(reader);
    if (!name || [members containsObject:name]) return nil;
    [members addObject:name];
    QONRemoteConfigV2SkipWhitespace(reader);
    if (!QONRemoteConfigV2Expect(reader, ':')) return nil;
    if ([name isEqualToString:@"raw"]) {
      raw = QONRemoteConfigV2ReadPortableSpan(reader, QONRemoteConfigV2MaximumRawValueBytes);
    } else if ([name isEqualToString:@"variation_uid"]) {
      variationUID = QONRemoteConfigV2ReadStringValue(reader);
    } else if ([name isEqualToString:@"apply_policy"]) {
      policyValue = QONRemoteConfigV2ReadStringValue(reader);
    } else if ([name isEqualToString:@"metadata"]) {
      metadata = QONRemoteConfigV2ReadPortableSpan(reader, QONRemoteConfigV2MaximumMetadataBytes);
    } else {
      return nil;
    }
    if (([name isEqualToString:@"raw"] && !raw) ||
        ([name isEqualToString:@"variation_uid"] && !variationUID) ||
        ([name isEqualToString:@"apply_policy"] && !policyValue) ||
        ([name isEqualToString:@"metadata"] && !metadata)) return nil;
    QONRemoteConfigV2SkipWhitespace(reader);
    if (QONRemoteConfigV2Consume(reader, '}')) break;
    if (!QONRemoteConfigV2Expect(reader, ',')) return nil;
    QONRemoteConfigV2SkipWhitespace(reader);
  }
  if (members.count != 4 || !raw || !metadata || !QONRemoteConfigV2ValidUID(variationUID)) return nil;
  QONRemoteConfigApplyPolicy policy;
  if ([policyValue isEqualToString:@"on_next_activate"]) {
    policy = QONRemoteConfigApplyPolicyOnNextActivate;
  } else if ([policyValue isEqualToString:@"immediate"]) {
    policy = QONRemoteConfigApplyPolicyImmediate;
  } else {
    return nil;
  }
  return [[QONRemoteConfigV2Entry alloc] initWithKey:key rawData:raw
      variationUID:variationUID applyPolicy:policy metadataData:metadata];
}

static NSDictionary<NSString *, QONRemoteConfigV2Entry *> *QONRemoteConfigV2ReadWireValues(
    QONRemoteConfigV2JSONReader *reader) {
  QONRemoteConfigV2SkipWhitespace(reader);
  if (!QONRemoteConfigV2Expect(reader, '{')) return nil;
  QONRemoteConfigV2SkipWhitespace(reader);
  NSMutableDictionary *values = [NSMutableDictionary new];
  if (QONRemoteConfigV2Consume(reader, '}')) return values;
  while (YES) {
    if (values.count >= QONRemoteConfigV2MaximumEntryCount) return nil;
    NSString *key = QONRemoteConfigV2ReadString(reader);
    if (!QONRemoteConfigV2ValidBoundedString(key, QONRemoteConfigV2MaximumKeyBytes) || values[key]) return nil;
    QONRemoteConfigV2SkipWhitespace(reader);
    if (!QONRemoteConfigV2Expect(reader, ':')) return nil;
    QONRemoteConfigV2Entry *entry = QONRemoteConfigV2ReadWireEntry(reader, key);
    if (!entry) return nil;
    values[key] = entry;
    QONRemoteConfigV2SkipWhitespace(reader);
    if (QONRemoteConfigV2Consume(reader, '}')) break;
    if (!QONRemoteConfigV2Expect(reader, ',')) return nil;
    QONRemoteConfigV2SkipWhitespace(reader);
  }
  return [values copy];
}

@interface QONRemoteConfigV2EnvelopeParser ()
- (nullable QONRemoteConfigV2Envelope *)parseBoundBody:(NSData *)body
                                             strongETag:(NSString *)strongETag;
@end

@implementation QONRemoteConfigV2EnvelopeParser

- (QONRemoteConfigV2Envelope *)parseBody:(NSData *)body
                              strongETag:(NSString *)strongETag
                             expectation:(QONRemoteConfigV2EnvelopeExpectation *)expectation {
  if (!expectation) return nil;
  QONRemoteConfigV2Envelope *envelope = [self parseBoundBody:body strongETag:strongETag];
  if (!envelope || envelope.projectID != expectation.projectID ||
      ![envelope.environmentUID isEqualToString:expectation.environmentUID]) return nil;
  // The normal case is a nil expectation fingerprint. The envelope's own value
  // is still shape-validated by parseBoundBody:, but it is a per-response tag
  // that rotates with the user's targeting context, so there is nothing here to
  // compare it against and nothing across fetches that it must equal.
  if (expectation.contextFingerprint &&
      ![envelope.contextFingerprint isEqualToString:expectation.contextFingerprint]) return nil;
  return envelope;
}

- (QONRemoteConfigV2Envelope *)parseBoundBody:(NSData *)body
                                    strongETag:(NSString *)strongETag {
  if (!body || body.length == 0 || body.length > QONRemoteConfigV2MaximumEnvelopeBytes) return nil;
  NSString *bodyDigest = nil;
  if (!QONRemoteConfigV2ValidStrongETag(strongETag, body, &bodyDigest)) return nil;
  NSString *strictUTF8 = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
  if (!strictUTF8 || ![[strictUTF8 dataUsingEncoding:NSUTF8StringEncoding] isEqual:body]) return nil;

  QONRemoteConfigV2JSONReader reader = {
    .bytes = body.bytes, .length = body.length, .index = 0, .limit = body.length,
  };
  int64_t schemaVersion = 0, projectID = 0, releaseNumber = 0;
  NSString *environmentUID = nil, *releaseUID = nil, *manifestHash = nil, *contextFingerprint = nil;
  NSDictionary<NSString *, QONRemoteConfigV2Entry *> *values = nil;
  BOOL completeKeySet = NO;
  BOOL hasSchema = NO, hasProject = NO, hasComplete = NO;
  NSMutableSet<NSString *> *members = [NSMutableSet new];
  QONRemoteConfigV2SkipWhitespace(&reader);
  if (!QONRemoteConfigV2Expect(&reader, '{')) return nil;
  QONRemoteConfigV2SkipWhitespace(&reader);
  if (QONRemoteConfigV2Consume(&reader, '}')) return nil;
  while (YES) {
    NSString *name = QONRemoteConfigV2ReadString(&reader);
    if (!name || [members containsObject:name]) return nil;
    [members addObject:name];
    QONRemoteConfigV2SkipWhitespace(&reader);
    if (!QONRemoteConfigV2Expect(&reader, ':')) return nil;
    if ([name isEqualToString:@"schema_version"]) {
      hasSchema = QONRemoteConfigV2ReadExactInteger(&reader, &schemaVersion);
    } else if ([name isEqualToString:@"project_id"]) {
      hasProject = QONRemoteConfigV2ReadExactInteger(&reader, &projectID);
    } else if ([name isEqualToString:@"environment_uid"]) {
      environmentUID = QONRemoteConfigV2ReadStringValue(&reader);
    } else if ([name isEqualToString:@"release_uid"]) {
      releaseUID = QONRemoteConfigV2ReadStringValue(&reader);
    } else if ([name isEqualToString:@"release_number"]) {
      if (!QONRemoteConfigV2ReadExactInteger(&reader, &releaseNumber)) return nil;
    } else if ([name isEqualToString:@"manifest_content_hash"]) {
      manifestHash = QONRemoteConfigV2ReadStringValue(&reader);
    } else if ([name isEqualToString:@"complete_key_set"]) {
      hasComplete = QONRemoteConfigV2ReadBooleanValue(&reader, &completeKeySet);
    } else if ([name isEqualToString:@"context_fingerprint"]) {
      contextFingerprint = QONRemoteConfigV2ReadStringValue(&reader);
    } else if ([name isEqualToString:@"values"]) {
      values = QONRemoteConfigV2ReadWireValues(&reader);
    } else {
      return nil;
    }
    if ((!hasSchema && [name isEqualToString:@"schema_version"]) ||
        (!hasProject && [name isEqualToString:@"project_id"]) ||
        (!hasComplete && [name isEqualToString:@"complete_key_set"]) ||
        ([name isEqualToString:@"environment_uid"] && !environmentUID) ||
        ([name isEqualToString:@"release_uid"] && !releaseUID) ||
        ([name isEqualToString:@"manifest_content_hash"] && !manifestHash) ||
        ([name isEqualToString:@"context_fingerprint"] && !contextFingerprint) ||
        ([name isEqualToString:@"values"] && !values)) return nil;
    QONRemoteConfigV2SkipWhitespace(&reader);
    if (QONRemoteConfigV2Consume(&reader, '}')) break;
    if (!QONRemoteConfigV2Expect(&reader, ',')) return nil;
    QONRemoteConfigV2SkipWhitespace(&reader);
  }
  QONRemoteConfigV2SkipWhitespace(&reader);
  if (reader.index != reader.length || members.count != 9 || schemaVersion != 1 || !completeKeySet ||
      projectID <= 0 || projectID > QONRemoteConfigV2MaximumSafeInteger ||
      releaseNumber <= 0 || releaseNumber > QONRemoteConfigV2MaximumSafeInteger ||
      releaseNumber > NSIntegerMax ||
      !QONRemoteConfigV2ValidUID(environmentUID) || !QONRemoteConfigV2ValidUID(releaseUID) ||
      !QONRemoteConfigV2ValidSHA256(manifestHash) ||
      [manifestHash isEqualToString:[@"0" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0]] ||
      !QONRemoteConfigV2ValidContextFingerprint(contextFingerprint) || !values) return nil;

  QONRemoteConfigV2Release *release = [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:releaseUID releaseNumber:(NSInteger)releaseNumber
      manifestContentHash:manifestHash entries:values canonicalBody:body
      strongETag:strongETag projectID:projectID contextFingerprint:contextFingerprint
      admissionOrdinal:0];
  if (!release) return nil;
  QONRemoteConfigV2Envelope *envelope = [QONRemoteConfigV2Envelope new];
  envelope.projectID = projectID;
  envelope.environmentUID = environmentUID;
  envelope.contextFingerprint = contextFingerprint;
  envelope.snapshotRelease = release;
  envelope.eTag = strongETag;
  envelope.bodyDigest = bodyDigest;
  envelope.canonicalBody = body;
  return envelope;
}

@end

@implementation QONRemoteConfigV2Entry

- (instancetype)initWithTombstoneKey:(NSString *)key {
  if (!QONRemoteConfigV2ValidBoundedString(key, QONRemoteConfigV2MaximumKeyBytes)) return nil;
  self = [super init];
  if (self) {
    _key = [key copy];
    _applyPolicy = QONRemoteConfigApplyPolicyOnNextActivate;
    _tombstone = YES;
  }
  return self;
}

- (instancetype)initWithKey:(NSString *)key
                     rawData:(NSData *)rawData
                variationUID:(NSString *)variationUID
                 applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
                    metadata:(id)metadata {
  id metadataCopy = QONRemoteConfigV2DeepJSONCopy(metadata);
  if (metadata && !metadataCopy) return nil;
  NSData *metadataData = metadataCopy ? [NSJSONSerialization dataWithJSONObject:metadataCopy
      options:NSJSONWritingFragmentsAllowed error:nil] : nil;
  return [self initWithKey:key rawData:rawData variationUID:variationUID
      applyPolicy:applyPolicy metadataObject:metadataCopy metadataData:metadataData];
}

- (instancetype)initWithKey:(NSString *)key
                     rawData:(NSData *)rawData
                variationUID:(NSString *)variationUID
                 applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
                metadataData:(NSData *)metadataData {
  id metadataObject = QONRemoteConfigPortableJSONObject(metadataData,
      QONRemoteConfigV2MaximumMetadataBytes);
  if (!metadataObject) return nil;
  return [self initWithKey:key rawData:rawData variationUID:variationUID
      applyPolicy:applyPolicy metadataObject:metadataObject metadataData:metadataData];
}

- (instancetype)initWithKey:(NSString *)key
                     rawData:(NSData *)rawData
                variationUID:(NSString *)variationUID
                 applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
              metadataObject:(id)metadataObject
                metadataData:(NSData *)metadataData {
  if (!QONRemoteConfigV2ValidBoundedString(key, QONRemoteConfigV2MaximumKeyBytes) ||
      rawData.length == 0 || rawData.length > QONRemoteConfigV2MaximumRawValueBytes ||
      !QONRemoteConfigV2ValidUID(variationUID) ||
      (applyPolicy != QONRemoteConfigApplyPolicyOnNextActivate &&
       applyPolicy != QONRemoteConfigApplyPolicyImmediate)) return nil;
  if (!QONRemoteConfigPortableJSONObject(rawData, QONRemoteConfigV2MaximumRawValueBytes)) return nil;
  if (metadataData.length > QONRemoteConfigV2MaximumMetadataBytes) return nil;
  self = [super init];
  if (self) {
    _key = [key copy];
    _rawData = [rawData copy];
    _variationUID = [variationUID copy];
    _applyPolicy = applyPolicy;
    _metadata = metadataObject == NSNull.null ? nil : metadataObject;
    _metadataData = [metadataData copy];
    _tombstone = NO;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)contentEquals:(QONRemoteConfigV2Entry *)other {
  if (!other) return NO;
  return [self.key isEqualToString:other.key] &&
      self.isTombstone == other.isTombstone &&
      ((self.rawData == nil && other.rawData == nil) || [self.rawData isEqual:other.rawData]) &&
      ((self.variationUID == nil && other.variationUID == nil) || [self.variationUID isEqual:other.variationUID]) &&
      self.applyPolicy == other.applyPolicy &&
      ((self.metadataData == nil && other.metadataData == nil) || [self.metadataData isEqual:other.metadataData]);
}

@end

@implementation QONRemoteConfigV2Release

- (instancetype)initWithReleaseUID:(NSString *)releaseUID
                      releaseNumber:(NSInteger)releaseNumber
                manifestContentHash:(NSString *)manifestContentHash
                            entries:(NSDictionary<NSString *,QONRemoteConfigV2Entry *> *)entries {
  return [self initWithReleaseUID:releaseUID releaseNumber:releaseNumber
      manifestContentHash:manifestContentHash entries:entries canonicalBody:nil
      strongETag:nil projectID:0 contextFingerprint:nil admissionOrdinal:0];
}

- (instancetype)initWithReleaseUID:(NSString *)releaseUID
                      releaseNumber:(NSInteger)releaseNumber
                manifestContentHash:(NSString *)manifestContentHash
                            entries:(NSDictionary<NSString *,QONRemoteConfigV2Entry *> *)entries
                      canonicalBody:(NSData *)canonicalBody
                          strongETag:(NSString *)strongETag
                           projectID:(int64_t)projectID
                  contextFingerprint:(NSString *)contextFingerprint
                   admissionOrdinal:(int64_t)admissionOrdinal {
  if (!QONRemoteConfigV2ValidUID(releaseUID) || releaseNumber <= 0 ||
      releaseNumber > QONRemoteConfigV2MaximumSafeInteger ||
      !QONRemoteConfigV2ValidSHA256(manifestContentHash) || !entries ||
      admissionOrdinal < 0 ||
      projectID < 0 || projectID > QONRemoteConfigV2MaximumSafeInteger ||
      (contextFingerprint && !QONRemoteConfigV2ValidSHA256(contextFingerprint)) ||
      ((canonicalBody == nil) != (strongETag == nil)) ||
      ((canonicalBody == nil) != (projectID == 0)) ||
      canonicalBody.length > QONRemoteConfigV2MaximumEnvelopeBytes) return nil;
  if (canonicalBody && !QONRemoteConfigV2ValidStrongETag(strongETag, canonicalBody, NULL)) return nil;
  NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:entries.count];
  NSUInteger valueCount = 0, tombstoneCount = 0;
  NSUInteger totalValueBytes = [releaseUID lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
      [manifestContentHash lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  if (totalValueBytes > QONRemoteConfigV2MaximumTotalValueBytes) return nil;
  for (id key in entries) {
    QONRemoteConfigV2Entry *entry = entries[key];
    if (![key isKindOfClass:NSString.class] || ![entry isKindOfClass:QONRemoteConfigV2Entry.class] ||
        ![key isEqualToString:entry.key]) return nil;
    if (entry.isTombstone) tombstoneCount += 1; else valueCount += 1;
    if (valueCount > QONRemoteConfigV2MaximumEntryCount ||
        tombstoneCount > QONRemoteConfigV2MaximumEntryCount) return nil;
    NSData *metadataData = entry.metadataData;
    NSUInteger entryBytes = [entry.key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
        [entry.variationUID lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
        entry.rawData.length + metadataData.length;
    if (entryBytes > QONRemoteConfigV2MaximumTotalValueBytes - totalValueBytes) return nil;
    totalValueBytes += entryBytes;
    copy[key] = entry;
  }
  self = [super init];
  if (self) {
    _releaseUID = [releaseUID copy];
    _releaseNumber = releaseNumber;
    _manifestContentHash = [manifestContentHash copy];
    _entries = [copy copy];
    _canonicalBody = [canonicalBody copy];
    _strongETag = [strongETag copy];
    _projectID = projectID;
    _contextFingerprint = [contextFingerprint copy];
    _admissionOrdinal = admissionOrdinal;
  }
  return self;
}

- (QONRemoteConfigV2Release *)releaseBySettingAdmissionOrdinal:(int64_t)admissionOrdinal {
  return [[QONRemoteConfigV2Release alloc] initWithReleaseUID:self.releaseUID
      releaseNumber:self.releaseNumber manifestContentHash:self.manifestContentHash
      entries:self.entries canonicalBody:self.canonicalBody strongETag:self.strongETag
      projectID:self.projectID contextFingerprint:self.contextFingerprint
      admissionOrdinal:admissionOrdinal];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)containsImmediateEntry {
  for (QONRemoteConfigV2Entry *entry in self.entries.allValues) {
    if (entry.applyPolicy == QONRemoteConfigApplyPolicyImmediate) return YES;
  }
  return NO;
}

- (BOOL)contentEquals:(QONRemoteConfigV2Release *)other {
  if (!other || ![self.releaseUID isEqualToString:other.releaseUID] ||
      self.releaseNumber != other.releaseNumber ||
      ![self.manifestContentHash isEqualToString:other.manifestContentHash] ||
      !((self.contextFingerprint == nil && other.contextFingerprint == nil) ||
        [self.contextFingerprint isEqual:other.contextFingerprint]) ||
      self.entries.count != other.entries.count) return NO;
  for (NSString *key in self.entries) {
    if (![self.entries[key] contentEquals:other.entries[key]]) return NO;
  }
  return YES;
}

@end

@implementation QONRemoteConfigV2State

- (instancetype)initWithCandidate:(QONRemoteConfigV2Release *)candidate
                            active:(QONRemoteConfigV2Release *)active
                          previous:(QONRemoteConfigV2Release *)previous
                       didActivate:(BOOL)didActivate {
  int64_t latest = MAX(candidate.admissionOrdinal,
      MAX(active.admissionOrdinal, previous.admissionOrdinal));
  return [self initWithCandidate:candidate active:active previous:previous
      didActivate:didActivate latestAdmissionOrdinal:latest];
}

- (instancetype)initWithCandidate:(QONRemoteConfigV2Release *)candidate
                            active:(QONRemoteConfigV2Release *)active
                          previous:(QONRemoteConfigV2Release *)previous
                       didActivate:(BOOL)didActivate
            latestAdmissionOrdinal:(int64_t)latestAdmissionOrdinal {
  int64_t highestSlotOrdinal = MAX(candidate.admissionOrdinal,
      MAX(active.admissionOrdinal, previous.admissionOrdinal));
  BOOL usesAdmissionOrdering = highestSlotOrdinal > 0;
  if ((!active && previous) || (!didActivate && (active || previous)) ||
      latestAdmissionOrdinal < 0 || latestAdmissionOrdinal < highestSlotOrdinal ||
      (candidate && active && usesAdmissionOrdering &&
       candidate.admissionOrdinal < active.admissionOrdinal) ||
      (candidate && active && usesAdmissionOrdering &&
       candidate.admissionOrdinal == active.admissionOrdinal &&
       ![candidate contentEquals:active]) ||
      (previous && active && usesAdmissionOrdering &&
       previous.admissionOrdinal >= active.admissionOrdinal) ||
      (candidate && active && !usesAdmissionOrdering &&
       candidate.releaseNumber < active.releaseNumber) ||
      (candidate && active && !usesAdmissionOrdering &&
       candidate.releaseNumber == active.releaseNumber && ![candidate contentEquals:active]) ||
      (previous && active && !usesAdmissionOrdering &&
       previous.releaseNumber >= active.releaseNumber)) return nil;
  self = [super init];
  if (self) {
    _candidate = candidate;
    _active = active;
    _previous = previous;
    _didActivate = didActivate;
    _latestAdmissionOrdinal = latestAdmissionOrdinal;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }

@end
