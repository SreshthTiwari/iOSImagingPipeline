#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(CameraModel, NSObject)

RCT_EXTERN_METHOD(startCamera:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(stopCamera:(RCTPromiseResolveBlock)resolver
                 rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(captureFrame:(RCTPromiseResolveBlock)resolver
                   rejecter:(RCTPromiseRejectBlock)reject)

@end
m
