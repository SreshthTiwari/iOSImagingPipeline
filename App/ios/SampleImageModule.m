#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(SampleImageModule, NSObject)

RCT_EXTERN_METHOD(getSampleImagePath:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)reject)

@end