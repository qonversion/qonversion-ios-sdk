#import <Foundation/Foundation.h>

@class QNLaunchResult;

NS_ASSUME_NONNULL_BEGIN

@interface QNAPIClient : NSObject

+ (instancetype)shared;

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) NSString *apiKey;

- (void)launchWithCompletion:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
