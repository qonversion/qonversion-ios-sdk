source 'https://github.com/CocoaPods/Specs.git'

project 'Qonversion'

target 'QonversionTests' do
  platform :ios, '9.0'
  pod 'OCMock'
end


target 'Sample' do
  platform :ios, '9.0'
  pod 'AppsFlyerFramework'
end


post_install do |installer|
  installer.pods_project.targets.each do |target|
    puts target.name
  end
end

