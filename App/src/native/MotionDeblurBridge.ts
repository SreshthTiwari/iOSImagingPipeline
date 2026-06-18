import {NativeModules} from 'react-native';

const {MotionDeblurModule} = NativeModules;

export const estimateMotionBlur = async (imagePath: string): Promise<{
  blurScore: number;
  isBlurry: boolean;
}> => {
  return MotionDeblurModule.estimateMotionBlur(imagePath);
};

export const removeMotionBlur = async (imagePath: string): Promise<string> => {
  return MotionDeblurModule.removeMotionBlur(imagePath);
};