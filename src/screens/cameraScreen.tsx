import React, {useMemo, useState} from 'react';
import {Alert, Image, StyleSheet, Text, View} from 'react-native';
import Button from '../components/Button';
import ImageCompare from '../components/ImageCompare';
import {computeBlurScore, isBlurry} from '../utils/blurMetrics';
import {captureFrame, startCamera, stopCamera} from '../native/CameraBridge';
import {applyPortraitEffect, applySharpnessRestore} from '../native/ProcessingBridge';

export default function CameraScreen() {
  const [isRunning, setIsRunning] = useState(false);
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
      await startCamera();
      setIsRunning(true);
      setStatus('Camera started');
    } catch (e) {
      Alert.alert('Camera error', 'Could not start camera.');
    }
  };

  const handleStop = async () => {
    try {
      await stopCamera();
      setIsRunning(false);
      setStatus('Camera stopped');
    } catch (e) {
      Alert.alert('Camera error', 'Could not stop camera.');
    }
  };

  const handleCapturePortrait = async () => {
    try {
      setStatus('Capturing frame...');
      const uri = await captureFrame();
      setOriginalUri(uri);

      setStatus('Applying portrait effect...');
      const portraitUri = await applyPortraitEffect(uri);
      setProcessedUri(portraitUri);

      setStatus('Portrait effect complete');
    } catch (e) {
      Alert.alert('Error', 'Failed to process portrait image.');
      setStatus('Error');
    }
  };

  const handleMotionCheck = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Capture a frame first.');
        return;
      }
      const score = await computeBlurScore(originalUri);
      setBlurScore(score);

      const restored = await applySharpnessRestore(originalUri);
      setProcessedUri(restored);

      setStatus(`Motion blur check complete`);
    } catch (e) {
      Alert.alert('Error', 'Failed to analyze blur.');
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.previewBox}>
        {originalUri ? (
          <ImageCompare leftUri={originalUri} rightUri={processedUri} />
        ) : (
          <View style={styles.placeholder}>
            <Text style={styles.placeholderText}>
              Camera preview / processed output will appear here
            </Text>
          </View>
        )}
      </View>

      <View style={styles.infoPanel}>
        <Text style={styles.label}>Status: <Text style={styles.value}>{status}</Text></Text>
        <Text style={styles.label}>Camera: <Text style={styles.value}>{isRunning ? 'Running' : 'Stopped'}</Text></Text>
        <Text style={styles.label}>Blur score: <Text style={styles.value}>{blurScore ?? '—'}</Text></Text>
        <Text style={styles.label}>Blur label: <Text style={styles.value}>{blurLabel}</Text></Text>
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
  placeholderText: {
    color: '#bbb',
    textAlign: 'center',
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
  buttonRow: {
    flexDirection: 'row',
    gap: 10,
  },
});