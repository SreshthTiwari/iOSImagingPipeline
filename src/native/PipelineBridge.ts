import {NativeModules} from 'react-native';
import {applyToneMapping} from './ToneMappingBridge';
import {applySceneEnhancement} from './SceneEnhancementBridge';
import {applySharpnessRestore} from './ProcessingBridge';
import {applyBokehEffect} from './BokehBridge';

const {PipelineModule} = NativeModules;

export const runFullPipeline = async (imagePath: string): Promise<string> => {
  if (PipelineModule?.runFullPipeline) {
    return PipelineModule.runFullPipeline(imagePath);
  }

  const toneMappedPath = await applyToneMapping(imagePath);
  const enhancedPath = await applySceneEnhancement(toneMappedPath);
  const sharpenedPath = await applySharpnessRestore(enhancedPath);
  const bokehPath = await applyBokehEffect(sharpenedPath);
  return bokehPath;
};