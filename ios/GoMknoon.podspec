Pod::Spec.new do |s|
  s.name         = 'GoMknoon'
  s.version      = '0.1.0'
  s.summary      = 'Go native library for libp2p (compiled via gomobile)'
  s.homepage     = 'https://github.com/mknoon'
  s.license      = { :type => 'MIT' }
  s.author       = 'mknoon'
  s.source       = { :path => '.' }
  s.ios.deployment_target = '13.0'
  s.vendored_frameworks = 'Runner/GoMknoon.xcframework'
  s.static_framework = true
  s.libraries = 'resolv'
end
