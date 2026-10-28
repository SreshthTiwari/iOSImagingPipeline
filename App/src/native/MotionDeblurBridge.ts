import {NativeModules} from 'react-native';

const {MotionDeblurModule} = NativeModules;

export type MotionDeblurResult =
  | {applied: false; path: string}
  | {applied: true; path: string; angleDegrees: number; lengthPixels: number};

export const estimateMotionBlur = async (imagePath: string): Promise<{
  blurScore: number;
  isBlurry: boolean;
}> => {
  return MotionDeblurModule.estimateMotionBlur(imagePath);
};

/**
 * Blind linear motion deblur. `applied: false` means the image was left untouched
 * (sharp, too noisy, or no trustworthy blur estimate), and `path` is the input.
 */
export const removeMotionBlur = async (imagePath: string): Promise<MotionDeblurResult> => {
  return MotionDeblurModule.removeMotionBlur(imagePath);
};
