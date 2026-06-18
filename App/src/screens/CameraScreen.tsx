import React, {useMemo, useState} from 'react';
import {
  Alert,
  ActivityIndicator,
  Image,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import Button from '../components/Button';
import ImageCompare from '../components/ImageCompare';
import FullscreenImageModal from '../components/FullscreenImageModal';
import {startCamera, stopCamera, captureFrame} from '../native/CameraBridge';
import {computeBlurScore, isBlurry} from '../native/BlurMetricsBridge';
import {applySharpnessRestore} from '../native/ProcessingBridge';
import {applyBokehEffect} from '../native/BokehBridge';
import {applyToneMapping} from '../native/ToneMappingBridge';
import {applySceneEnhancement} from '../native/SceneEnhancementBridge';
import {runFullPipeline} from '../native/PipelineBridge';
import {removeMotionBlur} from '../native/MotionDeblurBridge';

export default function CameraScreen() {
  const [isRunning, setIsRunning] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [originalUri, setOriginalUri] = useState<string | null>(null);
  const [processedUri, setProcessedUri] = useState<string | null>(null);
  const [blurScore, setBlurScore] = useState<number | null>(null);
  const [status, setStatus] = useState('Ready');
  const [fullscreenVisible, setFullscreenVisible] = useState(false);

  const blurLabel = useMemo(() => {
    if (blurScore === null) return '—';
    return isBlurry(blurScore) ? 'Blurry' : 'Sharp';
  }, [blurScore]);

  const handleStart = async () => {
    try {
      setStatus('Starting camera...');
      await startCamera();
      setIsRunning(true);
      setStatus('Camera started');
    } catch (error) {
      console.error('startCamera error', error);
      Alert.alert(
        'Camera error',
        'Could not start camera. Make sure camera permission is enabled.',
      );
      setStatus('Start failed');
    }
  };

  const handleStop = async () => {
    try {
      setStatus('Stopping camera...');
      await stopCamera();
      setIsRunning(false);
      setStatus('Camera stopped');
    } catch {
      Alert.alert('Camera error', 'Could not stop camera.');
      setStatus('Stop failed');
    }
  };

  const handleCapture = async () => {
    try {
      setIsProcessing(true);
      setStatus('Capturing frame...');
      const uri = await captureFrame();
      setOriginalUri(`file://${uri}`);
      setProcessedUri(null);
      setBlurScore(null);
      setStatus('Frame captured');
    } catch (error) {
      console.error('captureFrame error', error);
      Alert.alert('Error', 'Failed to capture image.');
      setStatus('Capture failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleMotionAnalysis = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture an image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Analyzing blur...');
      const score = await computeBlurScore(originalUri.replace('file://', ''));
      setBlurScore(score);
      setStatus('Motion analysis complete');
    } catch {
      Alert.alert('Error', 'Motion analysis failed.');
      setStatus('Motion analysis failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleSharpen = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture an image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Applying sharpening...');
      const outputPath = await applySharpnessRestore(originalUri.replace('file://', ''));
      setProcessedUri(`file://${outputPath}`);
      setStatus('Sharpen complete');
    } catch {
      Alert.alert('Error', 'Sharpening failed.');
      setStatus('Sharpen failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleBokeh = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture an image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Applying bokeh...');
      const outputPath = await applyBokehEffect(originalUri.replace('file://', ''));
      setProcessedUri(`file://${outputPath}`);
      setStatus('Bokeh complete');
    } catch {
      Alert.alert('Error', 'Bokeh failed.');
      setStatus('Bokeh failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleToneMap = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture an image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Applying tone mapping...');
      const outputPath = await applyToneMapping(originalUri.replace('file://', ''));
      setProcessedUri(`file://${outputPath}`);
      setStatus('Tone mapping complete');
    } catch {
      Alert.alert('Error', 'Tone mapping failed.');
      setStatus('Tone mapping failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleSceneEnhance = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture an image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Applying scene enhancement...');
      const outputPath = await applySceneEnhancement(originalUri.replace('file://', ''));
      setProcessedUri(`file://${outputPath}`);
      setStatus('Scene enhancement complete');
    } catch {
      Alert.alert('Error', 'Scene enhancement failed.');
      setStatus('Scene enhancement failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleFullPipeline = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture an image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Running full pipeline...');
      const outputPath = await runFullPipeline(originalUri.replace('file://', ''));
      setProcessedUri(`file://${outputPath}`);
      setStatus('Full pipeline complete');
    } catch (error) {
      console.error('runFullPipeline error', error);
      Alert.alert('Error', String(error) || 'Full pipeline failed.');
      setStatus('Full pipeline failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleMotionDeblur = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture an image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Removing motion blur...');
      const outputPath = await removeMotionBlur(originalUri.replace('file://', ''));
      setProcessedUri(`file://${outputPath}`);
      setStatus('Motion deblur complete');
    } catch (error) {
      console.error('removeMotionBlur error', error);
      Alert.alert('Error', String(error) || 'Motion deblur failed.');
      setStatus('Motion deblur failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleViewFullscreen = () => {
    if (!processedUri) {
      Alert.alert('No processed image', 'Process an image first.');
      return;
    }
    setFullscreenVisible(true);
  };

  return (
    <>
    <View style={styles.container}>
      <View style={styles.previewBox}>
        {originalUri && processedUri ? (
          <ImageCompare leftUri={originalUri} rightUri={processedUri} />
        ) : originalUri ? (
          <Image source={{uri: originalUri}} style={styles.previewImage} />
        ) : (
          <View style={styles.placeholder}>
            <Text style={styles.placeholderText}>
              Start the camera and capture a frame
            </Text>
          </View>
        )}
      </View>

      <View style={styles.infoPanel}>
        <Text style={styles.label}>
          Status: <Text style={styles.value}>{status}</Text>
        </Text>
        <Text style={styles.label}>
          Camera: <Text style={styles.value}>{isRunning ? 'Running' : 'Stopped'}</Text>
        </Text>
        <Text style={styles.label}>
          Blur score: <Text style={styles.value}>{blurScore ?? '—'}</Text>
        </Text>
        <Text style={styles.label}>
          Blur label: <Text style={styles.value}>{blurLabel}</Text>
        </Text>

        {isProcessing && (
          <View style={styles.processingRow}>
            <ActivityIndicator color="#fff" />
            <Text style={styles.processingText}>Processing...</Text>
          </View>
        )}
      </View>

      <View style={styles.buttonRow}>
        <Button title="Start Camera" onPress={handleStart} />
        <Button title="Stop Camera" onPress={handleStop} variant="secondary" />
      </View>

      <View style={styles.buttonRow}>
        <Button title="Capture Frame" onPress={handleCapture} />
        <Button title="Motion Analysis" onPress={handleMotionAnalysis} variant="secondary" />
      </View>

      <View style={styles.buttonRow}>
        <Button title="Sharpen" onPress={handleSharpen} />
        <Button title="Bokeh" onPress={handleBokeh} variant="secondary" />
      </View>

      <View style={styles.buttonRow}>
        <Button title="Tone Map" onPress={handleToneMap} />
        <Button title="Scene Enhance" onPress={handleSceneEnhance} variant="secondary" />
      </View>

      <View style={styles.buttonRow}>
        <Button title="Motion Deblur" onPress={handleMotionDeblur} />
        <Button title="Run Pipeline" onPress={handleFullPipeline} variant="secondary" />
      </View>

      <View style={styles.buttonRow}>
        <Button title="View Fullscreen" onPress={handleViewFullscreen} />
      </View>
    </View>
    <FullscreenImageModal
      visible={fullscreenVisible}
      imageUri={processedUri}
      onClose={() => setFullscreenVisible(false)}
    />
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    gap: 12,
  },
  previewBox: {
    flex: 1,
    backgroundColor: '#15151c',
    borderRadius: 16,
    overflow: 'hidden',
  },
  previewImage: {
    width: '100%',
    height: '100%',
    resizeMode: 'contain',
  },
  placeholder: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  placeholderText: {
    color: '#fff',
    textAlign: 'center',
    fontSize: 16,
    fontWeight: '600',
  },
  infoPanel: {
    backgroundColor: '#15151c',
    padding: 12,
    borderRadius: 12,
  },
  label: {
    color: '#d0d0d0',
    marginBottom: 4,
  },
  value: {
    color: '#fff',
    fontWeight: '600',
  },
  processingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginTop: 8,
  },
  processingText: {
    color: '#fff',
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 10,
  },
});