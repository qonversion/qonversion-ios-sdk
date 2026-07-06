#
# Be sure to run `pod lib lint Qonversion.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
    s.name             = 'Qonversion'
 	s.version          = '6.0.0'
 	s.swift_version = '5.5'
	s.summary 		= 'qonversion.io'
    s.description  = <<-DESC
  Deep Analytics for iOS Subscriptions
    Qonversion is the data platform to power in-app subscription revenue growth. Qonversion allows fast in-app subscriptions implementation. It provides the back-end infrastructure to validate user receipts and manage cross-platform user access to paid content on your app, so you do not need to build your own server. Qonversion also provides comprehensive subscription analytics and out-of-the-box integrations with the leading marketing, attribution, and product analytics platforms.
  DESC

    s.homepage                  = 'https://github.com/qonversion/qonversion-ios-sdk'
    s.license                   = { :type => 'MIT', :file => 'LICENSE' }
    s.author                    = { 'Qonversion Inc.' => 'hi@qonversion.io' }
    s.source                    = { :git => 'https://github.com/qonversion/qonversion-ios-sdk.git', :tag => s.version.to_s }
    s.framework                 = 'StoreKit'
    s.ios.deployment_target = '13.0'
    s.osx.deployment_target     = '10.15'
    s.tvos.deployment_target    = '13.0'
    s.watchos.deployment_target = '6.0'
    s.ios.frameworks            = ['UIKit', 'WebKit']
    s.requires_arc              = true
    s.resource_bundles          = {'Qonversion' => ['Sources/PrivacyInfo.xcprivacy']}
end
