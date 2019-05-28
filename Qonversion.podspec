
Pod::Spec.new do |s|
  s.name             = 'Qonversion'
  s.version          = '0.2.0'
  s.summary          = 'qonversion.io'
  s.description      = <<-DESC
  Qonversion Analytic Tool for Subscribrions
                       DESC
  s.homepage         = 'https://github.com/axcic/Qonversion2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'axcic' => 'bogdan.nov@ya.ru' }
  s.source           = { :git => 'https://github.com/axcic/Qonversion2.git', :tag => s.version.to_s }
  s.ios.deployment_target = '9.0'
  s.source_files = 'Qonversion/Classes/**/*'
  
end
