//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<flutter_background_geolocation/TSBackgroundGeolocationPlugin.h>)
#import <flutter_background_geolocation/TSBackgroundGeolocationPlugin.h>
#else
@import flutter_background_geolocation;
#endif

#if __has_include(<google_maps_flutter_ios/FGMGoogleMapsPlugin.h>)
#import <google_maps_flutter_ios/FGMGoogleMapsPlugin.h>
#else
@import google_maps_flutter_ios;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [TSBackgroundGeolocationPlugin registerWithRegistrar:[registry registrarForPlugin:@"TSBackgroundGeolocationPlugin"]];
  [FGMGoogleMapsPlugin registerWithRegistrar:[registry registrarForPlugin:@"FGMGoogleMapsPlugin"]];
}

@end
