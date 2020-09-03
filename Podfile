source 'https://github.com/CocoaPods/Specs.git'

project 'Qonversion'

target 'QonversionTests' do
  platform :ios, '9.0'
  pod 'OCMock', '~> 3.2.1'
end

target 'Sample App' do
  platform :ios, '9.0'
  pod 'SwiftyStoreKit'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    puts target.name
  end
end

