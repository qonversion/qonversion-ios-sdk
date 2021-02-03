Pod::Spec.new do |s|
  excluded_files = ['Sources/Qonversion/QONAutomations.h', 'Sources/Qonversion/QONAutomations.m', 'Sources/Qonversion/QONAutomationsFlowCoordinator.h', 'Sources/Qonversion/QONAutomationsFlowCoordinator.m', 'Sources/Qonversion/QONAutomationsViewController.h', 'Sources/Qonversion/QONAutomationsViewController.m', 'Sources/Qonversion/QONAutomationsDelegate.h', 'Sources/Qonversion/QONAutomationsDelegate.m', 'Sources/Qonversion/QONAutomationsActionsHandler.h', 'Sources/Qonversion/QONAutomationsActionsHandler.m', 'Sources/Qonversion/QONAutomationsFlowAssembly.h', 'Sources/Qonversion/QONAutomationsFlowAssembly.m', 'Sources/Qonversion/QONActionResult.h', 'Sources/Qonversion/QONActionResult.m']
  s.name             = 'Qonversion'
  s.version          = '2.9.1'
  s.summary          = 'qonversion.io'
  s.description      = <<-DESC
  Deep Analytics for iOS Subscriptions
    Qonversion is the data platform to power in-app subscription revenue growth. Qonversion allows fast in-app subscriptions implementation. It provides the back-end infrastructure to validate user receipts and manage cross-platform user access to paid content on your app, so you do not need to build your own server. Qonversion also provides comprehensive subscription analytics and out-of-the-box integrations with the leading marketing, attribution, and product analytics platforms.
  DESC
  s.homepage         = 'https://github.com/qonversion/qonversion-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Qonversion Inc.' => 'hi@qonversion.io' }
  s.source_files     = 'Sources/Qonversion/*.{h,m}'
  s.osx.exclude_files = excluded_files
  s.tvos.exclude_files = excluded_files
  s.watchos.exclude_files = excluded_files
  s.source           = { :git => 'https://github.com/qonversion/qonversion-ios-sdk.git', :tag => s.version.to_s }
  s.ios.deployment_target = '9.0'
  s.osx.deployment_target = '10.12'
  s.watchos.deployment_target = '6.2'
  s.ios.frameworks = ['UIKit', 'WebKit']
  s.requires_arc           = true
  
end
