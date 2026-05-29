#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(PipelineModule, NSObject)

RCT_EXTERN_METHOD(runFullPipeline:(NSString *)imagePath
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

@end