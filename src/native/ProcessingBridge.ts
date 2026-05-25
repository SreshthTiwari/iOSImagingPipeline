// JS-side wrapper for native iOS processing.
// Replace mocked logic with Vision/Core Image native module calls later.

export async function applyPortraitEffect(imageUri: string): Promise<string> {
  // Mock: return same image for now.
  // Later this would return a segmented + background-blurred output.
  return Promise.resolve(imageUri);
}

export async function applySharpnessRestore(imageUri: string): Promise<string> {
  // Mock: return same image for now.
  // Later this would return sharpened/restored image.
  return Promise.resolve(imageUri);
}