#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(SceneEnhancementModule, NSObject)

RCT_EXTERN_METHOD(applySceneEnhancement:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

@end