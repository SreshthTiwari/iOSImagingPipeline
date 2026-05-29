// // import React, {useMemo, useState} from 'react';
// // import {Alert, ActivityIndicator, StyleSheet, Text, View} from 'react-native';
// // import Button from '../components/Button';
// // import ImageCompare from '../components/ImageCompare';
// // import {computeBlurScore, isBlurry} from '../utils/blurMetrics';
// // import {captureFrame, startCamera, stopCamera} from '../native/CameraBridge';
// // import {applyPortraitEffect, applySharpnessRestore} from '../native/ProcessingBridge';

// // export default function CameraScreen() {
// //   const [isRunning, setIsRunning] = useState(false);
// //   const [isProcessing, setIsProcessing] = useState(false);
// //   const [originalUri, setOriginalUri] = useState<string | null>(null);
// //   const [processedUri, setProcessedUri] = useState<string | null>(null);
// //   const [blurScore, setBlurScore] = useState<number | null>(null);
// //   const [status, setStatus] = useState('Ready');

// //   const blurLabel = useMemo(() => {
// //     if (blurScore === null) return '—';
// //     return isBlurry(blurScore) ? 'Blurry' : 'Sharp';
// //   }, [blurScore]);

// //   const handleStart = async () => {
// //     try {
// //       setStatus('Starting camera...');
// //       await startCamera();
// //       setIsRunning(true);
// //       setStatus('Camera started');
// //     } catch {
// //       Alert.alert('Camera error', 'Could not start camera.');
// //       setStatus('Start failed');
// //     }
// //   };

// //   const handleStop = async () => {
// //     try {
// //       setStatus('Stopping camera...');
// //       await stopCamera();
// //       setIsRunning(false);
// //       setStatus('Camera stopped');
// //     } catch {
// //       Alert.alert('Camera error', 'Could not stop camera.');
// //       setStatus('Stop failed');
// //     }
// //   };

// //   const handleCapturePortrait = async () => {
// //     try {
// //       setIsProcessing(true);
// //       setStatus('Capturing frame...');
// //       const uri = await captureFrame();
// //       setOriginalUri(uri);

// //       setStatus('Applying portrait effect...');
// //       const portraitUri = await applyPortraitEffect(uri);
// //       setProcessedUri(portraitUri);

// //       setStatus('Portrait effect complete');
// //     } catch {
// //       Alert.alert('Error', 'Failed to process portrait image.');
// //       setStatus('Portrait processing failed');
// //     } finally {
// //       setIsProcessing(false);
// //     }
// //   };

// //   const handleMotionCheck = async () => {
// //     try {
// //       if (!originalUri) {
// //         Alert.alert('No image', 'Capture a frame first.');
// //         return;
// //       }

// //       setIsProcessing(true);
// //       setStatus('Analyzing blur...');
// //       const score = await computeBlurScore(originalUri);
// //       setBlurScore(score);

// //       setStatus('Applying restoration...');
// //       const restored = await applySharpnessRestore(originalUri);
// //       setProcessedUri(restored);

// //       setStatus('Motion blur check complete');
// //     } catch {
// //       Alert.alert('Error', 'Failed to analyze blur.');
// //       setStatus('Blur analysis failed');
// //     } finally {
// //       setIsProcessing(false);
// //     }
// //   };

// //   return (
// //     <View style={styles.container}>
// //       <View style={styles.previewBox}>
// //         {originalUri && processedUri ? (
// //           <ImageCompare leftUri={originalUri} rightUri={processedUri} />
// //         ) : originalUri ? (
// //           <View style={styles.singleImageState}>
// //             <Text style={styles.placeholderText}>Captured image ready</Text>
// //             <Text style={styles.placeholderSubtext}>
// //               Run portrait or motion processing to generate an output.
// //             </Text>
// //           </View>
// //         ) : (
// //           <View style={styles.placeholder}>
// //             <Text style={styles.placeholderText}>
// //               Capture an image to begin processing
// //             </Text>
// //           </View>
// //         )}
// //       </View>

// //       <View style={styles.infoPanel}>
// //         <Text style={styles.label}>
// //           Status: <Text style={styles.value}>{status}</Text>
// //         </Text>
// //         <Text style={styles.label}>
// //           Camera: <Text style={styles.value}>{isRunning ? 'Running' : 'Stopped'}</Text>
// //         </Text>
// //         <Text style={styles.label}>
// //           Blur score: <Text style={styles.value}>{blurScore ?? '—'}</Text>
// //         </Text>
// //         <Text style={styles.label}>
// //           Blur label: <Text style={styles.value}>{blurLabel}</Text>
// //         </Text>
// //         {isProcessing && (
// //           <View style={styles.processingRow}>
// //             <ActivityIndicator color="#fff" />
// //             <Text style={styles.processingText}>Processing...</Text>
// //           </View>
// //         )}
// //       </View>

// //       <View style={styles.buttonRow}>
// //         <Button title="Start Camera" onPress={handleStart} />
// //         <Button title="Stop Camera" onPress={handleStop} variant="secondary" />
// //       </View>

// //       <View style={styles.buttonRow}>
// //         <Button title="Portrait Effect" onPress={handleCapturePortrait} />
// //         <Button title="Motion Blur Check" onPress={handleMotionCheck} variant="secondary" />
// //       </View>
// //     </View>
// //   );
// // }

// // const styles = StyleSheet.create({
// //   container: {
// //     flex: 1,
// //     padding: 16,
// //     gap: 12,
// //   },
// //   previewBox: {
// //     flex: 1,
// //     backgroundColor: '#15151c',
// //     borderRadius: 16,
// //     overflow: 'hidden',
// //   },
// //   placeholder: {
// //     flex: 1,
// //     alignItems: 'center',
// //     justifyContent: 'center',
// //     padding: 20,
// //   },
// //   singleImageState: {
// //     flex: 1,
// //     alignItems: 'center',
// //     justifyContent: 'center',
// //     padding: 20,
// //   },
// //   placeholderText: {
// //     color: '#fff',
// //     textAlign: 'center',
// //     fontSize: 16,
// //     fontWeight: '600',
// //   },
// //   placeholderSubtext: {
// //     color: '#bbb',
// //     textAlign: 'center',
// //     marginTop: 8,
// //   },
// //   infoPanel: {
// //     backgroundColor: '#15151c',
// //     padding: 12,
// //     borderRadius: 12,
// //   },
// //   label: {
// //     color: '#d0d0d0',
// //     marginBottom: 4,
// //   },
// //   value: {
// //     color: '#fff',
// //     fontWeight: '600',
// //   },
// //   processingRow: {
// //     flexDirection: 'row',
// //     alignItems: 'center',
// //     gap: 10,
// //     marginTop: 8,
// //   },
// //   processingText: {
// //     color: '#fff',
// //   },
// //   buttonRow: {
// //     flexDirection: 'row',
// //     gap: 10,
// //   },
// // });
// import React, {useMemo, useState} from 'react';
// import {Alert, ActivityIndicator, Image, StyleSheet, Text, View} from 'react-native';
// import Button from '../components/Button';
// import ImageCompare from '../components/ImageCompare';
// import {getSampleImagePath} from '../native/SampleImageBridge';
// import {applyPortraitEffect, applySharpnessRestore} from '../native/ProcessingBridge';
// import {computeBlurScore, isBlurry} from '../native/BlurMetricsBridge';

// export default function CameraScreen() {
//   const [isProcessing, setIsProcessing] = useState(false);
//   const [originalUri, setOriginalUri] = useState<string | null>(null);
//   const [processedUri, setProcessedUri] = useState<string | null>(null);
//   const [blurScore, setBlurScore] = useState<number | null>(null);
//   const [status, setStatus] = useState('Ready');

//   const blurLabel = useMemo(() => {
//     if (blurScore === null) return '—';
//     return isBlurry(blurScore) ? 'Blurry' : 'Sharp';
//   }, [blurScore]);

//   const handleLoadSample = async () => {
//     try {
//       setIsProcessing(true);
//       setStatus('Loading sample image...');
//       const path = await getSampleImagePath();
//       setOriginalUri(`file://${path}`);
//       setProcessedUri(null);
//       setBlurScore(null);
//       setStatus('Sample image loaded');
//     } catch (e) {
//       Alert.alert('Error', 'Could not load sample image.');
//       setStatus('Load failed');
//     } finally {
//       setIsProcessing(false);
//     }
//   };

//   const handlePortraitEffect = async () => {
//     try {
//       if (!originalUri) {
//         Alert.alert('No image', 'Load a sample image first.');
//         return;
//       }

//       setIsProcessing(true);
//       setStatus('Applying portrait effect...');
//       const outputPath = await applyPortraitEffect(originalUri.replace('file://', ''));
//       setProcessedUri(`file://${outputPath}`);
//       setStatus('Portrait effect complete');
//     } catch {
//       Alert.alert('Error', 'Failed to apply portrait effect.');
//       setStatus('Portrait failed');
//     } finally {
//       setIsProcessing(false);
//     }
//   };

//   const handleBlurAnalysis = async () => {
//     try {
//       if (!originalUri) {
//         Alert.alert('No image', 'Load a sample image first.');
//         return;
//       }

//       setIsProcessing(true);
//       setStatus('Analyzing blur...');
//       const score = await computeBlurScore(originalUri.replace('file://', ''));
//       setBlurScore(score);
//       setStatus('Blur analysis complete');
//     } catch {
//       Alert.alert('Error', 'Failed to analyze blur.');
//       setStatus('Blur analysis failed');
//     } finally {
//       setIsProcessing(false);
//     }
//   };

//   const handleSharpen = async () => {
//     try {
//       if (!originalUri) {
//         Alert.alert('No image', 'Load a sample image first.');
//         return;
//       }

//       setIsProcessing(true);
//       setStatus('Applying sharpening...');
//       const outputPath = await applySharpnessRestore(originalUri.replace('file://', ''));
//       setProcessedUri(`file://${outputPath}`);
//       setStatus('Sharpening complete');
//     } catch {
//       Alert.alert('Error', 'Failed to sharpen image.');
//       setStatus('Sharpening failed');
//     } finally {
//       setIsProcessing(false);
//     }
//   };

//   return (
//     <View style={styles.container}>
//       <View style={styles.previewBox}>
//         {originalUri && processedUri ? (
//           <ImageCompare leftUri={originalUri} rightUri={processedUri} />
//         ) : originalUri ? (
//           <Image source={{uri: originalUri}} style={styles.previewImage} />
//         ) : (
//           <View style={styles.placeholder}>
//             <Text style={styles.placeholderText}>Load a sample image to begin</Text>
//           </View>
//         )}
//       </View>

//       <View style={styles.infoPanel}>
//         <Text style={styles.label}>
//           Status: <Text style={styles.value}>{status}</Text>
//         </Text>
//         <Text style={styles.label}>
//           Blur score: <Text style={styles.value}>{blurScore ?? '—'}</Text>
//         </Text>
//         <Text style={styles.label}>
//           Blur label: <Text style={styles.value}>{blurLabel}</Text>
//         </Text>

//         {isProcessing && (
//           <View style={styles.processingRow}>
//             <ActivityIndicator color="#fff" />
//             <Text style={styles.processingText}>Processing...</Text>
//           </View>
//         )}
//       </View>

//       <View style={styles.buttonRow}>
//         <Button title="Load Sample" onPress={handleLoadSample} />
//         <Button title="Portrait Effect" onPress={handlePortraitEffect} variant="secondary" />
//       </View>

//       <View style={styles.buttonRow}>
//         <Button title="Analyze Blur" onPress={handleBlurAnalysis} />
//         <Button title="Sharpen" onPress={handleSharpen} variant="secondary" />
//       </View>
//     </View>
//   );
// }

// const styles = StyleSheet.create({
//   container: {flex: 1, padding: 16, gap: 12},
//   previewBox: {flex: 1, backgroundColor: '#15151c', borderRadius: 16, overflow: 'hidden'},
//   previewImage: {width: '100%', height: '100%', resizeMode: 'contain'},
//   placeholder: {flex: 1, alignItems: 'center', justifyContent: 'center', padding: 20},
//   placeholderText: {color: '#fff', textAlign: 'center', fontSize: 16, fontWeight: '600'},
//   infoPanel: {backgroundColor: '#15151c', padding: 12, borderRadius: 12},
//   label: {color: '#d0d0d0', marginBottom: 4},
//   value: {color: '#fff', fontWeight: '600'},
//   processingRow: {flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 8},
//   processingText: {color: '#fff'},
//   buttonRow: {flexDirection: 'row', gap: 10},
// });

import React, {useMemo, useState} from 'react';
import {Alert, ActivityIndicator, Image, StyleSheet, Text, View} from 'react-native';
import Button from '../components/Button';
import ImageCompare from '../components/ImageCompare';
import {getSampleImagePath} from '../native/SampleImageBridge';
import {computeBlurScore, isBlurry} from '../native/BlurMetricsBridge';
import {applySharpnessRestore} from '../native/ProcessingBridge';
import {applyBokehEffect} from '../native/BokehBridge';
import {applyToneMapping} from '../native/ToneMappingBridge';
import {applySceneEnhancement} from '../native/SceneEnhancementBridge';
import {runFullPipeline} from '../native/PipelineBridge';

export default function CameraScreen() {
  const [isProcessing, setIsProcessing] = useState(false);
  const [originalUri, setOriginalUri] = useState<string | null>(null);
  const [processedUri, setProcessedUri] = useState<string | null>(null);
  const [blurScore, setBlurScore] = useState<number | null>(null);
  const [status, setStatus] = useState('Ready');

  const blurLabel = useMemo(() => {
    if (blurScore === null) return '—';
    return isBlurry(blurScore) ? 'Blurry' : 'Sharp';
  }, [blurScore]);

  const loadSample = async () => {
    try {
      setIsProcessing(true);
      setStatus('Loading sample image...');
      const path = await getSampleImagePath();
      setOriginalUri(`file://${path}`);
      setProcessedUri(null);
      setBlurScore(null);
      setStatus('Sample image loaded');
    } catch {
      Alert.alert('Error', 'Could not load sample image.');
      setStatus('Load failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const motionAnalysis = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Load a sample image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Analyzing motion blur...');
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

  const sharpen = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Load a sample image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Sharpening image...');
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

  const bokeh = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Load a sample image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Applying bokeh...');
      const outputPath = await applyBokehEffect(originalUri.replace('file://', ''));
      setProcessedUri(`file://${outputPath}`);
      setStatus('Bokeh complete');
    } catch {
      Alert.alert('Error', 'Bokeh effect failed.');
      setStatus('Bokeh failed');
    } finally {
      setIsProcessing(false);
    }
  };

  const toneMap = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Load a sample image first.');
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

  const sceneEnhance = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Load a sample image first.');
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

  const fullPipeline = async () => {
    try {
      if (!originalUri) {
        Alert.alert('No image', 'Load a sample image first.');
        return;
      }
      setIsProcessing(true);
      setStatus('Running full pipeline...');
      const outputPath = await runFullPipeline(originalUri.replace('file://', ''));
      setProcessedUri(`file://${outputPath}`);
      setStatus('Full pipeline complete');
    } catch {
      Alert.alert('Error', 'Full pipeline failed.');
      setStatus('Full pipeline failed');
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
          <Image source={{uri: originalUri}} style={styles.previewImage} />
        ) : (
          <View style={styles.placeholder}>
            <Text style={styles.placeholderText}>Load a sample image to begin</Text>
          </View>
        )}
      </View>

      <View style={styles.infoPanel}>
        <Text style={styles.label}>
          Status: <Text style={styles.value}>{status}</Text>
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
        <Button title="Load Sample" onPress={loadSample} />
        <Button title="Motion Analysis" onPress={motionAnalysis} variant="secondary" />
      </View>

      <View style={styles.buttonRow}>
        <Button title="Sharpen" onPress={sharpen} />
        <Button title="Bokeh" onPress={bokeh} variant="secondary" />
      </View>

      <View style={styles.buttonRow}>
        <Button title="Tone Map" onPress={toneMap} />
        <Button title="Scene Enhance" onPress={sceneEnhance} variant="secondary" />
      </View>

      <View style={styles.buttonRow}>
        <Button title="Run Full Pipeline" onPress={fullPipeline} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, padding: 16, gap: 12},
  previewBox: {flex: 1, backgroundColor: '#15151c', borderRadius: 16, overflow: 'hidden'},
  previewImage: {width: '100%', height: '100%', resizeMode: 'contain'},
  placeholder: {flex: 1, alignItems: 'center', justifyContent: 'center', padding: 20},
  placeholderText: {color: '#fff', textAlign: 'center', fontSize: 16, fontWeight: '600'},
  infoPanel: {backgroundColor: '#15151c', padding: 12, borderRadius: 12},
  label: {color: '#d0d0d0', marginBottom: 4},
  value: {color: '#fff', fontWeight: '600'},
  processingRow: {flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 8},
  processingText: {color: '#fff'},
  buttonRow: {flexDirection: 'row', gap: 10},
});