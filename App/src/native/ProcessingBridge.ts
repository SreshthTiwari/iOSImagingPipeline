import {NativeModules} from 'react-native';

const {ProcessingModule} = NativeModules;

export const applyPortraitEffect = async (imagePath: string): Promise<string> => {
  return ProcessingModule.applyPortraitEffect(imagePath);
};

export const applySharpnessRestore = async (imagePath: string): Promise<string> => {
  return ProcessingModule.applySharpnessRestore(imagePath);
};