Pod::Spec.new do |s|
  s.name             = 'doclens'
  s.version          = '0.1.0'
  s.summary          = 'Document scanner with native edge detection and 100% Flutter UI.'
  s.description      = <<-DESC
Native-grade document edge detection (Apple Vision) + perspective warp, paired with fully customizable Flutter UI.
                       DESC
  s.homepage         = 'https://github.com/yourname/doclens'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'doclens' => 'noreply@doclens.dev' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
