#import "QNAttributionManager.h"
#import "QNAPIClient.h"
#import "QNUtils.h"

@interface QNAttributionManager()

@property (nonatomic) QNAPIClient *client;

@end

@implementation QNAttributionManager

- (instancetype)init
{
  self = [super init];
  if (self) {
    _client = [QNAPIClient shared];
  }
  return self;
}

- (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider {
  double delayInSeconds = 5.0;
  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));

  dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
    
    [_client attributionRequest:provider data:data completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
      if (dict && [dict respondsToSelector:@selector(valueForKey:)]) {
        QONVERSION_LOG(@"Attribution Request Log Response:\n%@", dict);
      }
    }];
  });
}

@end
