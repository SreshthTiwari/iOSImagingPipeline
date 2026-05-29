import React, {useMemo, useState} from 'react';
import {Alert, ActivityIndicator, StyleSheet, Text, View} from 'react-native';
import Button from '../components/Button';
import ImageCompare from '../components/ImageCompare';
import {computeBlurScore, isBlurry} from '../utils/blurMetrics';
import {captureFrame, startCamera, stopCamera} from '../native/CameraBridge';
import {applyPortraitEffect, applySharpnessRestore} from '../native/ProcessingBridge';

export default function CameraScreen() {
  const [isRunning, setIsRunning] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [originalUri, setOriginalUri] = useState<string | null>(null);
  const [processedUri, setProcessedUri] = useState<string | null>(null);
  const [blurScore, setBlurScore] = useState<number | null>(null);
  const [status, setStatus] = useState('Ready');

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
    } catch {
      Alert.alert('Camera error', 'Could not start camera.');
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

  const handleCapturePortrait = async () => {
    try {
      setIsProcessing(true);
      setStatus('Capturing frame...');
      const uri = await captureFrame();
      setOriginalUri(uri);

      setStatus('Applying portrait effect...');
      const portraitUri = await applyPortraitEffect(uri);
      setProcessedUri(portraitUri);

      setStatus('Portrait effect complete');
    } catch {
      Alert.alert('Error', 'Failed to process portrait image.');
      setStatus('Portrait processing failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleMotionCheck = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture a frame first.');
        return;
      }

      setIsProcessing(true);
      setStatus('Analyzing blur...');
      const score = await computeBlurScore(originalUri);
      setBlurScore(score);

      setStatus('Applying restoration...');
      const restored = await applySharpnessRestore(originalUri);
      setProcessedUri(restored);

      setStatus('Motion blur check complete');
    } catch {
      Alert.alert('Error', 'Failed to analyze blur.');
      setStatus('Blur analysis failed');
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.previewBox}>
        {originalUri && processedUri ? (
          <ImageCompare leftUri={originalUri} rightUri={processedUri} />
        ) : originalUri ? (
          <View style={styles.singleImageState}>
            <Text style={styles.placeholderText}>Captured image ready</Text>
            <Text style={styles.placeholderSubtext}>
              Run portrait or motion processing to generate an output.
            </Text>
          </View>
        ) : (
          <View style={styles.placeholder}>
            <Text style={styles.placeholderText}>
              Capture an image to begin processing
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
        <Button title="Portrait Effect" onPress={handleCapturePortrait} />
        <Button title="Motion Blur Check" onPress={handleMotionCheck} variant="secondary" />
      </View>
    </View>
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
  placeholder: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  singleImageState: {
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
  placeholderSubtext: {
    color: '#bbb',
    textAlign: 'center',
    marginTop: 8,
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