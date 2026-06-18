import {NativeModules} from 'react-native';

const {ToneMappingModule} = NativeModules;

export const applyToneMapping = async (imagePath: string): Promise<string> => {
  return ToneMappingModule.applyToneMapping(imagePath);
};