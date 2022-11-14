//
//  QONAutomationsScreenProcessor.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 09.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsScreenProcessor.h"
#import "Qonversion.h"
#import "QONMacrosProcess.h"

static NSString *const kMacrosRegex = @"\\[\\[.*?\\]\\]";
static NSString *const kMacrosCategoryKey = @"category";
static NSString *const kMacrosTypeKey = @"type";
static NSString *const kMacrosIDKey = @"uid";
static NSString *const kMacrosTypePrice = @"price";
static NSString *const kMacrosProductsCategory = @"product";
static NSString *const kMacrosSubscriptionDuration = @"subscription_duration";
static NSString *const kMacrosTrialDuration = @"trial_duration";

@interface QONAutomationsScreenProcessor ()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *macrosTypes;

@end

@implementation QONAutomationsScreenProcessor

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _macrosTypes = @{
      kMacrosTypePrice: @(QONScreenMacrosTypeProductPrice),
      kMacrosSubscriptionDuration: @(QONScreenMacrosTypeProductSubscriptionDuration),
      kMacrosTrialDuration: @(QONScreenMacrosTypeProductTrialDuration)
    };
  }
  
  return self;
}

- (void)processScreen:(NSString *)htmlString completion:(QONAutomationsScreenProcessorCompletionHandler)completion {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kMacrosRegex options:NSRegularExpressionCaseInsensitive error:nil];
  NSArray<NSTextCheckingResult *> *regexResult = [regex matchesInString:htmlString options:0 range:NSMakeRange(0, htmlString.length - 1)];
  
  NSMutableArray<QONMacrosProcess *> *macroses = [NSMutableArray new];
  
  for (NSTextCheckingResult *result in regexResult) {
    NSString *resultString = [htmlString substringWithRange:result.range];
    
    QONMacrosProcess *macros = [self prepareMacrosFromData:resultString];
    if (macros) {
      [macroses addObject:macros];
    }
  }
  
  NSArray<QONMacrosProcess *> *resultMacroses = [macroses copy];
  if (resultMacroses.count > 0) {
    [self processMacroses:resultMacroses originalHTML:htmlString completion:completion];
  } else {
    completion(htmlString, nil);
  }
}

- (void)processMacroses:(NSArray<QONMacrosProcess *> *)macroses originalHTML:(NSString *)htmlString completion:(QONAutomationsScreenProcessorCompletionHandler)completion {
  [[Qonversion sharedInstance] products:^(NSDictionary<NSString *,QONProduct *> * _Nonnull result, NSError * _Nullable error) {
    if (error) {
      completion(nil, error);
    }
    
    __block NSString *html = [htmlString copy];
    
    for (QONMacrosProcess *macrosProcess in macroses) {
      QONProduct *product = result[macrosProcess.productID];
      if (!product) {
        continue;
      }
      
      switch (macrosProcess.type) {
        case QONScreenMacrosTypeProductPrice: {
          NSRange range = [html rangeOfString:macrosProcess.initialMacrosString];
          html = [html stringByReplacingCharactersInRange:range withString:product.prettyPrice];
          
          break;
        }
        default:
          break;
      }
    }
    
    completion(html, nil);
  }];
}

- (QONMacrosProcess * _Nullable)prepareMacrosFromData:(NSString *)data {
  NSString *formattedData = [self removeUselessMacrosSymbols:data];
  NSData *jsonData = [formattedData dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:nil];
  NSString *category = result[kMacrosCategoryKey];
  NSString *macrosType = result[kMacrosTypeKey];
  NSString *identifier = result[kMacrosIDKey];
  
  if (![category isEqualToString:kMacrosProductsCategory] || identifier.length == 0) {
    return nil;
  }

  NSNumber *typeValue = self.macrosTypes[macrosType];
  QONScreenMacrosType type = typeValue ? typeValue.integerValue : QONScreenMacrosTypeUnknown;
  QONMacrosProcess *macros = [QONMacrosProcess new];
  macros.productID = identifier;
  macros.type = type;
  macros.initialMacrosString = data;
  
  return macros;
}

- (NSString *)removeUselessMacrosSymbols:(NSString *)string {
  NSString *result = [string stringByReplacingCharactersInRange:NSMakeRange(0, 2) withString:@""];
  result = [result stringByReplacingCharactersInRange:NSMakeRange(result.length - 2, 2) withString:@""];
  result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  
  return result;
}

@end
