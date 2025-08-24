platform :ios, '14.0'

def shared_pods
  pod 'GoogleMLKit/TextRecognition'
  
  pod 'SwiftyJSON', '~> 4.0'
end

target 'MateCameraFix' do
  use_frameworks!
  shared_pods
end

target 'MateCameraFixTests' do
  use_frameworks!
  shared_pods
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      config.build_settings['ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end
end
