import {NativeModules} from 'react-native';

const {BlurMetricsModule} = NativeModules;

export const computeBlurScore = async (imagePath: string): Promise<number> => {
  return BlurMetricsModule.computeBlurScore(imagePath);
};

export const isBlurry = (score: number, threshold = 150): boolean => {
  return score < threshold;
};