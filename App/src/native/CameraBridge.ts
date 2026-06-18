import {NativeModules} from 'react-native';

const {CameraModel} = NativeModules;

export const startCamera = async (): Promise<string> => {
  return CameraModel.startCamera();
};

export const stopCamera = async (): Promise<string> => {
  return CameraModel.stopCamera();
};

export const captureFrame = async (): Promise<string> => {
  return CameraModel.captureFrame();
};