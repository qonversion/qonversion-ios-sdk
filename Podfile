source 'https://github.com/CocoaPods/Specs.git'

project 'Qonversion'
use_frameworks!

target 'Sample' do
platform :ios, 13.0
end


post_install do |installer|
  installer.pods_project.targets.each do |target|
    puts target.name
  end
end
