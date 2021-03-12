//
//  QONAutomationsScreenProcessor.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 09.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsScreenProcessor.h"
#import "Qonversion.h"

static NSString *const kMacrosRegex = @"\\{\\{.*\\}\\}";
static NSString *const kMacrosSeparator = @"->";
static NSString *const kProductsMacrosPrefix = @"products";
static NSString *const kMacrosPrice = @"price";
static NSString *const kMacrosSubscriptionDuration = @"subscription_duration";
static NSString *const kMacrosTrialDuration = @"trial_duration";

typedef NS_ENUM(NSInteger, QONScreenMacrosType) {
  QONScreenMacrosTypeUnknown = 0,
  QONScreenMacrosTypeProductPrice = 1,
  QONScreenMacrosTypeProductSubscriptionDuration = 2,
  QONScreenMacrosTypeProductTrialDuration = 3
};

@interface QONMacrosProcess : NSObject

@property (nonatomic, assign) QONScreenMacrosType type;
@property (nonatomic, assign) NSRange range;
@property (nonatomic, copy) NSString *productID;


@end

@implementation QONMacrosProcess

@end

@interface QONAutomationsScreenProcessor ()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *macrosTypes;

@end

@implementation QONAutomationsScreenProcessor

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _macrosTypes = @{
      kMacrosPrice: @(QONScreenMacrosTypeProductPrice),
      kMacrosSubscriptionDuration: @(QONScreenMacrosTypeProductSubscriptionDuration),
      kMacrosTrialDuration: @(QONScreenMacrosTypeProductTrialDuration)
    };
  }
  
  return self;
}

- (void)processScreen:(NSString *)htmlString completion:(QONAutomationsScreenProcessCompletionHandler)completion {
  NSURL *url = [[NSBundle bundleWithIdentifier:@"com.qonversion.Qonversion"] URLForResource:@"page" withExtension:@"html"];
  NSError *error;
  htmlString = [NSString stringWithContentsOfURL:url encoding:NSStringEncodingConversionAllowLossy error:&error];
  
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kMacrosRegex options:NSRegularExpressionCaseInsensitive error:nil];
  NSArray<NSTextCheckingResult *> *regexResult = [regex matchesInString:htmlString options:nil range:NSMakeRange(0, htmlString.length - 1)];
  
  NSMutableArray<QONMacrosProcess *> *resultMacroses = [NSMutableArray new];
  
  for (NSTextCheckingResult *result in regexResult) {
    NSString *resultString = [htmlString substringWithRange:result.range];
    resultString = [self removeUselessMacrosSymbols:resultString];
    
    NSArray<NSString *> *parsedResult = [resultString componentsSeparatedByString:kMacrosSeparator];
    
    QONMacrosProcess *macros = [self prepareMacrosFromData:parsedResult range:result.range];
    if (macros) {
      [resultMacroses addObject:macros];
    }
  }
  
  [self processMacroses:[resultMacroses copy] originalHTML:htmlString completion:completion];
}

- (void)processMacroses:(NSArray<QONMacrosProcess *> *)macroses originalHTML:(NSString *)htmlString completion:(QONAutomationsScreenProcessCompletionHandler)completion {
  [Qonversion products:^(NSDictionary<NSString *,QNProduct *> * _Nonnull result, NSError * _Nullable error) {
    if (error) {
      completion(nil, error);
    }
    
    __block NSString *html = [htmlString copy];
    
    for (QONMacrosProcess *macrosProcess in macroses) {
      QNProduct *product = result[macrosProcess.productID];
      if (!product) {
        continue;
      }
      
      switch (macrosProcess.type) {
        case QONScreenMacrosTypeProductPrice:
          html = [html stringByReplacingCharactersInRange:macrosProcess.range withString:product.prettyPrice];
          break;
        case QONScreenMacrosTypeProductSubscriptionDuration:
//          html = [html stringByReplacingCharactersInRange:macrosProcess.range withString:product.duration];
          break;
        case QONScreenMacrosTypeProductTrialDuration:
//          html = [html stringByReplacingCharactersInRange:macrosProcess.range withString:product.trialDuration];
          break;
          
        default:
          break;
      }
    }
    
    completion(html, nil);
  }];
}

- (NSString *)removeUselessMacrosSymbols:(NSString *)string {
  NSString *result = [string stringByReplacingCharactersInRange:NSMakeRange(0, 2) withString:@""];
  result = [result stringByReplacingCharactersInRange:NSMakeRange(result.length - 2, 2) withString:@""];
  result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  
  return result;
}

- (QONMacrosProcess * _Nullable)prepareMacrosFromData:(NSArray *)data range:(NSRange)range {
  if (![data.firstObject isEqualToString:kProductsMacrosPrefix] || data.count < 3) {
    return nil;
  }
  
  NSString *productID = data[1];
  NSString *macrosType = data[2];
  NSNumber *typeValue = self.macrosTypes[macrosType];
  QONScreenMacrosType type = typeValue ? typeValue.integerValue : QONScreenMacrosTypeUnknown;
  QONMacrosProcess *macros = [QONMacrosProcess new];
  macros.productID = productID;
  macros.type = type;
  macros.range = range;
  
  return macros;
}

- (void)doIt:(NSArray *)data {
  
}

@end
