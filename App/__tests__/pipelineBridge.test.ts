const calls: string[] = [];

const stage = (name: string) =>
  jest.fn(async (path: string) => {
    calls.push(name);
    return `${path}>${name}`;
  });

jest.mock('../src/native/ToneMappingBridge', () => ({
  applyToneMapping: stage('tone'),
}));
jest.mock('../src/native/SceneEnhancementBridge', () => ({
  applySceneEnhancement: stage('scene'),
}));
jest.mock('../src/native/ProcessingBridge', () => ({
  applySharpnessRestore: stage('sharpen'),
}));
jest.mock('../src/native/BokehBridge', () => ({
  applyBokehEffect: stage('bokeh'),
}));

describe('runFullPipeline JS fallback', () => {
  beforeEach(() => {
    calls.length = 0;
    jest.resetModules();
  });

  it('chains tone map, scene enhance, sharpen, bokeh, each on the previous output', async () => {
    const {runFullPipeline} = require('../src/native/PipelineBridge');

    const out = await runFullPipeline('/in.jpg');

    expect(calls).toEqual(['tone', 'scene', 'sharpen', 'bokeh']);
    expect(out).toBe('/in.jpg>tone>scene>sharpen>bokeh');
  });

  it('prefers the native PipelineModule when it is registered', async () => {
    const {NativeModules} = require('react-native');
    NativeModules.PipelineModule = {
      runFullPipeline: jest.fn().mockResolvedValue('/native.jpg'),
    };
    const {runFullPipeline} = require('../src/native/PipelineBridge');

    await expect(runFullPipeline('/in.jpg')).resolves.toBe('/native.jpg');
    expect(calls).toEqual([]);
  });
});
