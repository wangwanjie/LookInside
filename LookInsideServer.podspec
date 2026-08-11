Pod::Spec.new do |spec|
  spec.name = 'LookInsideServer'
  spec.version = '2.3.10-kg'
  spec.summary = 'Local development pod for the LookInsideServer XCFramework.'
  spec.description = <<-DESC
    Binary CocoaPods wrapper for LookInsideServer.xcframework used in local
    development via `pod 'LookInsideServer', :path => '...'`.
  DESC
  spec.homepage = 'https://github.com/LookInsideApp/LookInside'
  spec.license = { :type => 'GPL-3.0', :file => 'LICENSE' }
  spec.author = { 'HenryLi' => 'henryli@tencentmusic.com' }
  spec.source = { :http => "http://172.17.13.138/ftpfanxingroot/#{spec.name}/#{spec.version}.zip", :type => "zip" }

  spec.ios.deployment_target = '13.0'
  spec.osx.deployment_target = '14.0'

  spec.vendored_frameworks = 'LookInsideServer.xcframework'
  spec.preserve_paths = 'LookInsideServer.xcframework'
  spec.requires_arc = false
end
