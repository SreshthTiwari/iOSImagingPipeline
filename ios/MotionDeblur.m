#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(MotionDeblurModule, NSObject)

RCT_EXTERN_METHOD(estimateMotionBlur:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(removeMotionBlur:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

@end