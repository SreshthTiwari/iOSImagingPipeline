#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(BlurMetricsModule, NSObject)

RCT_EXTERN_METHOD(computeBlurScore:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

@end