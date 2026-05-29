#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(BokehModule, NSObject)

RCT_EXTERN_METHOD(applyBokehEffect:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

@end