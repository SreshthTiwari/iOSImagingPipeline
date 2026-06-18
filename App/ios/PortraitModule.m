#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ProcessingModule, NSObject)

RCT_EXTERN_METHOD(applyPortraitEffect:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(applySharpnessRestore:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

@end