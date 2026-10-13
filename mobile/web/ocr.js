(() => {
  let tesseractPromise;
  let workerPromise;

  const loadTesseract = () => {
    if (window.Tesseract) return Promise.resolve();
    tesseractPromise ??= new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src =
        'https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.min.js';
      script.onload = resolve;
      script.onerror = () =>
        reject(new Error('Could not download the local OCR engine.'));
      document.head.appendChild(script);
    });
    return tesseractPromise;
  };

  window.foodScanRecognizeText = async (imageDataUrl) => {
    await loadTesseract();
    workerPromise ??= window.Tesseract.createWorker('eng');
    try {
      const worker = await workerPromise;
      const { data } = await worker.recognize(imageDataUrl);
      return data.text;
    } catch (error) {
      workerPromise = undefined;
      throw error;
    }
  };
})();
