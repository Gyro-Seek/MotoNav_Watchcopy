# MotoNav iOS 版（版本见 MotoNav/Config.swift）
# 高德导航（自带 3D 地图）+ 高德搜索
platform :ios, '15.0'

target 'MotoNav' do
  use_frameworks!
  pod 'AMapNavi'
  pod 'AMapSearch'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |c|
      c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      # 高德 SDK 没有给 M 芯片电脑的模拟器编译版本：模拟器只编 x86_64（真机不受影响）
      c.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end
end
