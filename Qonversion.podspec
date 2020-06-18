Pod::Spec.new do |s|
  s.name             = 'Qonversion'
  s.version          = '1.2.0'
  s.summary          = 'qonversion.io'
  s.description      = <<-DESC
  Deep Analytics for iOS Subscriptions
    Get a read on how your apps are doing in an instant and come to critical decisions quicker.
  App revenue analytics.
    Powerful yet simple subscription analytics. Conversion from install to paying user, MRR, LTV, churn.
    Feed the advertising and analytics tools you are already using with the data on high-value users to improve your ads targeting and marketing ROAS.
                       DESC
  s.homepage         = 'https://github.com/qonversion/qonversion-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Qonversion Inc.' => 'hi@qonversion.io' }
  s.source           = { :git => 'https://github.com/qonversion/qonversion-ios-sdk.git', :tag => s.version.to_s }
  s.ios.deployment_target = '9.0'
  s.source_files = 'Sources/**/*'

end
