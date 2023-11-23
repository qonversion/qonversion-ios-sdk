//
//  QONAutomationsNavigationController.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.01.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsNavigationController.h"

#if TARGET_OS_IOS

@interface QONAutomationsNavigationController ()

@end

@implementation QONAutomationsNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
  return UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

@end

#endif
