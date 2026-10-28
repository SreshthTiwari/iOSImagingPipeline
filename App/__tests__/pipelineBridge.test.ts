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
const mockBokeh = stage('bokeh');
jest.mock('../src/native/BokehBridge', () => ({
  applyBokehEffect: (path: string) => mockBokeh(path),
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

  it('keeps the sharpened image when bokeh finds no person', async () => {
    mockBokeh.mockRejectedValueOnce(
      Object.assign(new Error('No person found'), {code: 'BOKEH_NO_SUBJECT'}),
    );
    const {runFullPipeline} = require('../src/native/PipelineBridge');

    await expect(runFullPipeline('/in.jpg')).resolves.toBe(
      '/in.jpg>tone>scene>sharpen',
    );
  });

  it('still fails the pipeline on other bokeh errors', async () => {
    mockBokeh.mockRejectedValueOnce(
      Object.assign(new Error('boom'), {code: 'BOKEH_ERROR'}),
    );
    const {runFullPipeline} = require('../src/native/PipelineBridge');

    await expect(runFullPipeline('/in.jpg')).rejects.toThrow('boom');
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
