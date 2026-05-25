export function computeBlurScore(imageUri: string): Promise<number> {
  // Prototype placeholder:
  // This will call native code
  // to compute sharpness metrics.
  return new Promise(resolve => {
    const fakeScore = 120 + Math.random() * 180;
    resolve(fakeScore);
  });
}

export function isBlurry(score: number, threshold = 180): boolean {
  return score < threshold;
}