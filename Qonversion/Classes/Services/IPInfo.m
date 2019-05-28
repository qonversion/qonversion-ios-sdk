//
//  IPInfo.m
//  Qonversion
//
//  Created by Bogdan Novikov on 24/05/2019.
//

#import "IPInfo.h"
#import "Keeper.h"

@interface IPInfo()

@property (nonatomic, readonly) NSMutableArray *sources;

@end

@implementation IPInfo

- (instancetype)init {
    self = super.init;
    if (self) {
        _sources = [NSMutableArray.alloc initWithObjects:
                    @"https://ifconfig.co/json",
                    @"https://ipapi.co/json",
                    @"https://api.myip.com/",
                    @"https://ifconfig.co/json", nil];
    }
    return self;
}

// MARK: - Framework Internal
- (void)fetchIP:(void (^)(void))completion {
    NSString *source = [self.sources lastObject];
    if (!source) {
        completion();
        return;
    }
    [self.sources removeLastObject];
    [self fetchIpBySource:source completion:^(NSString * _Nullable ip) {
        if (!ip) {
            [self fetchIP:completion];
            return;
        }
        if (!Keeper.initialIP) {
            [Keeper setInitialIP:ip];
        }
        completion();
    }];
}

// MARK: - Private
- (void)fetchIpBySource:(NSString *)source completion:(void (^)(NSString * _Nullable ip))completion {
    NSURL *url = [NSURL URLWithString:source];
    if (!url) {
        completion(nil);
        return;
    }
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    [[session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (!data) {
            completion(nil);
            return;
        }
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!dict) {
            return;
        }
        completion(dict[@"ip"]);
    }] resume];
}

@end
