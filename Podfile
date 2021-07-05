source 'https://github.com/CocoaPods/Specs.git'

project 'Qonversion'
use_frameworks!

target 'QonversionTests' do
  platform :ios, 12.0
  pod 'OCMock'
end


target 'Sample' do
platform :ios, 12.0
end

target 'WatchOS iOS' do
  pod 'Qonversion', :path => '.'
end

target 'WatchOS iOS Extension' do
  pod 'Qonversion', :path => '.'
end


post_install do |installer|
  installer.pods_project.targets.each do |target|
    puts target.name
  end
end

