import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Callback for tracking progress during upscaling
typedef ProgressCallback = void Function(double progress, String message);

class ImageUpscaler {
  OrtSession? _session;
  final int tileSize; // Tile size for processing
  final int? tileSizeOutput; // Tile size for output
  final int overlap; // Overlap between tiles to prevent seams

  ImageUpscaler({
    this.tileSize = 128, // Default tile size
    this.tileSizeOutput,
    this.overlap = 8, // Default overlap
  }) : assert(overlap < tileSize, 'Overlap must be smaller than tile size');

  /// Initialize the ONNX model from assets
  Future<void> initializeModel(String modelPath) async {
    final sessionOptions = OrtSessionOptions();
    try {
      OrtEnv.instance.init();

      // Optimize for mobile devices
      sessionOptions.setIntraOpNumThreads(10);
      sessionOptions.setInterOpNumThreads(10);
      sessionOptions.setSessionGraphOptimizationLevel(
        GraphOptimizationLevel.ortEnableAll,
      );

      final rawAssetFile = await rootBundle.load(modelPath);
      final bytes = rawAssetFile.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, sessionOptions);
    } catch (e) {
      throw Exception('Failed to initialize ONNX Runtime from assets: $e');
    } finally {
      sessionOptions.release();
    }
  }

  /// Initialize the ONNX model from a file on the device
  Future<void> initializeModelFromFile(String filePath) async {
    final sessionOptions = OrtSessionOptions();
    try {
      OrtEnv.instance.init();

      // Optimize for mobile devices
      sessionOptions.setIntraOpNumThreads(2);
      sessionOptions.setInterOpNumThreads(2);
      sessionOptions.setSessionGraphOptimizationLevel(
        GraphOptimizationLevel.ortEnableAll,
      );

      final file = File(filePath);
      final bytes = await file.readAsBytes();
      _session = OrtSession.fromBuffer(bytes, sessionOptions);
    } catch (e) {
      throw Exception('Failed to initialize ONNX Runtime from file: $e');
    } finally {
      sessionOptions.release();
    }
  }

  /// Upscale an image with the specified scale factor
  Future<ui.Image?> upscaleImage(
    ui.Image sourceImage, {
    int scale = 2,
    bool useTiling = true,
    ProgressCallback? onProgress,
  }) async {
    if (_session == null) {
      throw Exception('Model not initialized. Call initializeModel first.');
    }

    try {
      if (!useTiling ||
          (sourceImage.width <= tileSize && sourceImage.height <= tileSize)) {
        return await _processFullImage(sourceImage, scale, onProgress);
      } else {
        return await _processByTiles(sourceImage, scale, onProgress);
      }
    } catch (e) {
      rethrow;
      throw Exception('Error processing image: $e');
    }
  }

  Future<ui.Image> _processFullImage(
    ui.Image sourceImage,
    int scale,
    ProgressCallback? onProgress,
  ) async {
    const int TOTAL_STEPS = 4;
    int currentStep = 0;

    void updateProgress(String stage) {
      currentStep++;
      final progress = currentStep / TOTAL_STEPS;
      onProgress?.call(
        progress,
        'Processing full image: $stage (${(progress * 100).toStringAsFixed(1)}%)',
      );
    }

    // Step 1: Prepare input
    updateProgress('Preparing input');
    final inputTensor = await _prepareInputTensor(
      sourceImage,
      sourceImage.width,
      sourceImage.height,
      useTiling: false,
    );

    try {
      // Step 2: Run inference
      updateProgress('Running neural network');
      final outputs = await _runInference(inputTensor);

      // Step 3: Process output
      updateProgress('Processing output');
      final result = await _tensorToImage(
        outputs,
        (sourceImage.width * scale).toInt(),
        (sourceImage.height * scale).toInt(),
      );

      // Step 4: Finalizing
      updateProgress('Finalizing');

      return result;
    } finally {
      inputTensor.release();
    }
  }

  Future<ui.Image> _processByTiles(
    ui.Image sourceImage,
    int scale,
    ProgressCallback? onProgress,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    final numTilesX = (sourceImage.width / (tileSize - overlap)).ceil();
    final numTilesY = (sourceImage.height / (tileSize - overlap)).ceil();
    final totalTiles = numTilesX * numTilesY;
    int processedTiles = 0;

    // Calculate total steps for progress tracking
    const int STEPS_PER_TILE = 4; // Extract, prepare, process, draw
    final totalSteps = totalTiles * STEPS_PER_TILE;
    int currentStep = 0;

    void updateProgress(String stage) {
      currentStep++;
      final progress = currentStep / totalSteps;
      onProgress?.call(
        progress,
        'Tile ${processedTiles + 1}/$totalTiles: $stage (${(progress * 100).toStringAsFixed(1)}%)',
      );
    }

    for (int y = 0; y < numTilesY; y++) {
      for (int x = 0; x < numTilesX; x++) {
        // Calculate tile coordinates
        final tileX = x * (tileSize - overlap);
        final tileY = y * (tileSize - overlap);
        final tileWidth = math.min(tileSize, sourceImage.width - tileX);
        final tileHeight = math.min(tileSize, sourceImage.height - tileY);

        // Step 1: Extract tile
        updateProgress('Extracting tile');
        final tile = await _extractTile(
          sourceImage,
          tileX,
          tileY,
          tileWidth,
          tileHeight,
        );

        // Step 2: Prepare tensor
        updateProgress('Preparing tensor');
        final inputTensor = await _prepareInputTensor(
          tile,
          tileWidth,
          tileHeight,
        );

        try {
          // Step 3: Process tile
          updateProgress('Processing');
          final outputs = await _runInference(inputTensor);

          if (tileSizeOutput != null) {
            final tileXOutput = x * (tileSizeOutput! - overlap);
            final tileYOutput = y * (tileSizeOutput! - overlap);
            final tileWidthOutput = math.min(
              tileSizeOutput!,
              sourceImage.width - tileXOutput,
            );
            final tileHeightOutput = math.min(
              tileSizeOutput!,
              sourceImage.height - tileYOutput,
            );
            final processedTile = await _tensorToImage(
              outputs,
              (tileWidthOutput * scale).toInt(),
              (tileHeightOutput * scale).toInt(),
            );

            // Step 4: Draw tile
            updateProgress('Drawing tile');
            final outputX = tileXOutput * scale;
            final outputY = tileYOutput * scale;
            canvas.drawImage(
              processedTile,
              Offset(outputX.toDouble(), outputY.toDouble()),
              paint,
            );
          } else {
            final processedTile = await _tensorToImage(
              outputs,
              (tileWidth * scale).toInt(),
              (tileHeight * scale).toInt(),
            );

            // Step 4: Draw tile
            updateProgress('Drawing tile');
            final outputX = tileX * scale;
            final outputY = tileY * scale;
            canvas.drawImage(
              processedTile,
              Offset(outputX.toDouble(), outputY.toDouble()),
              paint,
            );
          }
        } finally {
          inputTensor.release();
        }
        processedTiles++;
      }
    }

    // Final progress update
    onProgress?.call(1.0, 'Finalizing image...');

    final finalWidth = sourceImage.width * scale;
    final finalHeight = sourceImage.height * scale;
    final picture = recorder.endRecording();
    return await picture.toImage(finalWidth, finalHeight);
  }

  Future<ui.Image> _extractTile(
    ui.Image source,
    int x,
    int y,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImageRect(
      source,
      Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        width.toDouble(),
        height.toDouble(),
      ),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint(),
    );

    return await recorder.endRecording().toImage(width, height);
  }

  Future<OrtValueTensor> _prepareInputTensor(
    ui.Image image,
    int width,
    int height,
    {
      bool useTiling = true
    }
  ) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) throw Exception('Failed to get image bytes');

    final rgbaList = bytes.buffer.asUint8List();
    final inputData = Float32List(3 * (useTiling ? tileSize : width) * (useTiling ? tileSize : height));
    if (useTiling) {
      inputData.fillRange(0, inputData.length, 0.0);
    }

    for (int i = 0; i < width * height; i++) {
      for (int c = 0; c < 3; c++) {
        inputData[c * width * height + i] = rgbaList[i * 4 + c] / 255.0;
      }
    }

    return OrtValueTensor.createTensorWithDataList(inputData, [
      1,
      3,
      (useTiling ? tileSize : width),
      (useTiling ? tileSize : height),
    ]);
  }

  Future<List<dynamic>> _runInference(OrtValueTensor inputTensor) async {
    final runOptions = OrtRunOptions();
    try {
      final outputs = await _session!.runAsync(runOptions, {
        'input': inputTensor,
      });
      return outputs?[0]?.value as List;
    } finally {
      runOptions.release();
    }
  }

  Future<Uint8List> _tensorToBytes(
    List<dynamic> outputs,
    int finalWidth,
    int finalHeight,
  ) async {
    final pixels = Uint8List(finalWidth * finalHeight * 4);
    int index = 0;

    for (int y = 0; y < finalHeight; y++) {
      for (int x = 0; x < finalWidth; x++) {
        pixels[index++] = (outputs[0][0][y][x] * 255).clamp(0, 255).toInt();
        pixels[index++] = (outputs[0][1][y][x] * 255).clamp(0, 255).toInt();
        pixels[index++] = (outputs[0][2][y][x] * 255).clamp(0, 255).toInt();
        pixels[index++] = 255;
      }
    }

    return pixels;
  }

  Future<ui.Image> _tensorToImage(
    List<dynamic> outputs,
    int finalWidth,
    int finalHeight,
  ) async {
    final pixels = await _tensorToBytes(outputs, finalWidth, finalHeight);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      finalWidth,
      finalHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Dispose of the upscaler and free resources
  void dispose() {
    _session?.release();
    _session = null;
  }
}
