#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ToneMappingModule, NSObject)

RCT_EXTERN_METHOD(applyToneMapping:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

@end