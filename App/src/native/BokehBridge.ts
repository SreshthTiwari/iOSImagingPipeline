import {NativeModules} from 'react-native';

const {BokehModule} = NativeModules;

export const applyBokehEffect = async (imagePath: string): Promise<string> => {
  return BokehModule.applyBokehEffect(imagePath);
};