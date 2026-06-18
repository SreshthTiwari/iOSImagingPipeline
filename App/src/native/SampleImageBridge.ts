import {NativeModules} from 'react-native';

const {SampleImageModule} = NativeModules;

export const getSampleImagePath = async (): Promise<string> => {
  return SampleImageModule.getSampleImagePath();
};