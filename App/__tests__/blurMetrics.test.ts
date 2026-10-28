import {NativeModules} from 'react-native';

const native = {computeBlurScore: jest.fn()};
NativeModules.BlurMetricsModule = native;

// require after the mock is installed: the bridge reads NativeModules at import time
const {computeBlurScore, isBlurry} = require('../src/native/BlurMetricsBridge');

describe('isBlurry', () => {
  it('flags scores below the default threshold', () => {
    expect(isBlurry(149.9)).toBe(true);
    expect(isBlurry(0)).toBe(true);
  });

  it('treats the threshold itself as sharp', () => {
    expect(isBlurry(150)).toBe(false);
    expect(isBlurry(900)).toBe(false);
  });

  it('honours a custom threshold', () => {
    expect(isBlurry(200, 250)).toBe(true);
    expect(isBlurry(200, 100)).toBe(false);
  });
});

describe('computeBlurScore', () => {
  it('forwards the image path to the native module', async () => {
    native.computeBlurScore.mockResolvedValue(321.5);

    await expect(computeBlurScore('/tmp/a.jpg')).resolves.toBe(321.5);
    expect(native.computeBlurScore).toHaveBeenCalledWith('/tmp/a.jpg');
  });
});
