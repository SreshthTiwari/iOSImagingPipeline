// This is a JS-side bridge wrapper.
// This will connect to a native module that uses AVFoundation.

export async function startCamera(): Promise<void> {
  // Mock for development
  return Promise.resolve();
}

export async function stopCamera(): Promise<void> {
  return Promise.resolve();
}

export async function captureFrame(): Promise<string> {
  // Mock image URI for testing UI on Windows.
  // Replace with a real image path or native capture result later.
  return Promise.resolve(
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=1200&q=80',
  );
}