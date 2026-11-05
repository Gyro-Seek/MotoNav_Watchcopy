// 版本：跟随 App 版本（见 Config.swift）
// 让 Swift 能用高德的 Objective-C SDK（不同版本的头文件位置可能不同，找得到哪个用哪个）
#import <AMapFoundationKit/AMapFoundationKit.h>
#import <AMapNaviKit/AMapNaviKit.h>
#if __has_include(<AMapNaviKit/MAMapKit.h>)
#import <AMapNaviKit/MAMapKit.h>
#elif __has_include(<MAMapKit/MAMapKit.h>)
#import <MAMapKit/MAMapKit.h>
#endif
#import <AMapSearchKit/AMapSearchKit.h>
