import {NativeModules} from 'react-native';

const {PipelineModule} = NativeModules;

export const runFullPipeline = async (imagePath: string): Promise<string> => {
  return PipelineModule.runFullPipeline(imagePath);
};