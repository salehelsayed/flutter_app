Pod::Spec.new do |s|
  s.name         = 'GoMknoonNSE'
  s.version      = '0.1.0'
  s.summary      = 'Memory-bounded crypto bridge for Mknoon notification previews'
  s.homepage     = 'https://github.com/mknoon'
  s.license      = { :type => 'MIT' }
  s.author       = 'mknoon'
  s.source       = { :path => '.' }
  s.ios.deployment_target = '13.0'
  s.vendored_frameworks = 'Runner/GoMknoonNSE.xcframework'
  s.static_framework = true
  s.libraries = 'resolv'
end
