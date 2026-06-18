import {NativeModules} from 'react-native';

const {SceneEnhancementModule} = NativeModules;

export const applySceneEnhancement = async (imagePath: string): Promise<string> => {
  return SceneEnhancementModule.applySceneEnhancement(imagePath);
};