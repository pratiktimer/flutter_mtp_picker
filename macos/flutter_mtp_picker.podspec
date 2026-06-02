Pod::Spec.new do |s|
  s.name             = 'flutter_mtp_picker'
  s.version          = '0.1.2'
  s.summary          = 'Browse and copy files from USB MTP devices.'
  s.description      = <<-DESC
A Flutter desktop plugin for browsing phone and camera storage over USB MTP APIs.
                       DESC
  s.homepage         = 'https://github.com/pratiktimer/flutter_mtp_picker'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'pratiktimer' => 'pratiktimer' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(inherited) /opt/homebrew/include /usr/local/include',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) /opt/homebrew/lib /usr/local/lib',
    'OTHER_LDFLAGS' => '$(inherited) -lmtp'
  }
end
