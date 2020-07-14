#import "QNAttributionManager.h"

@implementation QNAttributionManager

- (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
//  double delayInSeconds = 5.0;
//  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
//
//  dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
//    NSDictionary *body = [_requestSerializer attributionDataWithDict:data fromProvider:provider];
//    NSURLRequest *request = [[self requestBuilder] makeAttributionRequestWith:body];
//
//    [self dataTaskWithRequest:request completion:^(NSDictionary *dict) {
//      if (dict && [dict respondsToSelector:@selector(valueForKey:)]) {
//        QONVERSION_LOG(@"Attribution Request Log Response:\n%@", dict);
//      }
//    }];
//  });
}

@end
