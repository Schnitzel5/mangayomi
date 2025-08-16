import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:mangayomi/modules/manga/reader/reader_view.dart';
import 'package:mangayomi/utils/extensions/others.dart';
import 'package:mangayomi/utils/image_upscaling.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
part 'image_upscaling_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Uint8List?> upscaleImage(
  Ref ref, {
  required UChapDataPreload data,
  required bool upscale,
}) async {
  Uint8List? imageBytes;

  if (upscale) {
    imageBytes = await data.getImageBytes;

    if (imageBytes == null) {
      return null;
    }

    final sourceImage = await decodeImageFromList(imageBytes);
    final upscaler = ImageUpscaler(tileSize: 142, tileSizeOutput: 128, overlap: 0);
    ui.Image? upscaledImage;

    try {
      //await upscaler.initializeModel('assets/ColorizeArtistic_dyn.onnx');
      await upscaler.initializeModel('assets/waifu2x-noise0.onnx');
      //await upscaler.initializeModel('assets/Anime4K_Upscale_GAN_x2_S.onnx');

      upscaledImage = await upscaler.upscaleImage(
        sourceImage,
        scale: 2,
        useTiling: true,
        onProgress: (progress, message) {
          print('$message: ${(progress * 100).toStringAsFixed(1)}%');
        },
      );
    } catch (e, stack) {
      print(stack);
    } finally {
      upscaler.dispose();
    }

    final bytes = await upscaledImage?.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return bytes?.buffer.asUint8List();
  }
  return null;
}
