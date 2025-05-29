import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// For web, we'll use our custom methods
import 'web_impl.dart' if (dart.library.io) 'web_impl_stub.dart';

// Only import the package on mobile platforms
import 'package:flutter_image_compress/flutter_image_compress.dart'
    if (dart.library.html) 'web_image_compress_stub.dart';

/// Compress an image to a target file size (default 0.7MB)
/// Images smaller than target will be left untouched
/// For web, this uses canvas resize
/// For mobile, this uses flutter_image_compress with quality adjustments
Future<Uint8List> compressImage(
  Uint8List imageBytes, {
  int quality = 70,
  int targetWidth = 800,
  int? targetHeight,
  int? targetSizeBytes, // New parameter for custom target size
}) async {
  if (imageBytes.isEmpty) {
    return Uint8List(0);
  }

  // Use custom target size or default to 0.7MB (700KB)
  final int finalTargetSize = targetSizeBytes ?? (700 * 1024); // 700KB default

  // If image is already smaller than target, return it unchanged
  if (imageBytes.length <= finalTargetSize) {
    print(
        'Image already below ${(finalTargetSize / 1024 / 1024).toStringAsFixed(2)}MB (${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)}MB), skipping compression');
    return imageBytes;
  }

  try {
    if (kIsWeb) {
      // Web implementation - use binary search to reach target size
      return await _compressWebImageToTargetSize(
        imageBytes,
        finalTargetSize,
        targetWidth,
        targetHeight: targetHeight,
      );
    } else {
      // Mobile implementation - use binary search to reach target size
      return await _compressMobileImageToTargetSize(
        imageBytes,
        finalTargetSize,
        targetWidth,
        targetHeight: targetHeight,
      );
    }
  } catch (e) {
    print('Error compressing image: $e');
    // Return smaller compressed version as fallback
    try {
      // Last resort - apply aggressive compression
      if (kIsWeb) {
        return await resizeWebImage(imageBytes, 400, quality: 50);
      } else {
        return await FlutterImageCompress.compressWithList(
          imageBytes,
          quality: 50,
          minWidth: 400,
          minHeight: 0,
        );
      }
    } catch (e2) {
      print('Even fallback compression failed: $e2');
      return imageBytes;
    }
  }
}

/// Binary search approach to compress web image to target size
Future<Uint8List> _compressWebImageToTargetSize(
    Uint8List imageBytes, int targetSizeBytes, int targetWidth,
    {int? targetHeight}) async {
  // Start with full resolution and high quality to reach 700KB
  int currentWidth = targetWidth;
  int currentQuality = 85; // Start high

  Uint8List result = imageBytes;
  int attempts = 0;
  final int maxAttempts = 15;

  print(
      'Starting compression to reach ${(targetSizeBytes / 1024 / 1024).toStringAsFixed(2)}MB target');

  while (attempts < maxAttempts) {
    attempts++;

    // Compress with current settings
    Uint8List compressed = await resizeWebImage(imageBytes, currentWidth,
        targetHeight: targetHeight, quality: currentQuality);

    double sizeMB = compressed.length / (1024 * 1024);
    double targetMB = targetSizeBytes / (1024 * 1024);
    double diffMB = (compressed.length - targetSizeBytes) / (1024 * 1024);

    print(
        'Web compression attempt $attempts: Width=$currentWidth, Quality=$currentQuality, Size=${sizeMB.toStringAsFixed(2)}MB, Target=${targetMB.toStringAsFixed(2)}MB, Diff=${diffMB.toStringAsFixed(2)}MB');

    // If we're close enough (within 15% of target), use this result
    if ((compressed.length >= targetSizeBytes * 0.85) &&
        (compressed.length <= targetSizeBytes * 1.15)) {
      result = compressed;
      print('Target reached! Final size: ${sizeMB.toStringAsFixed(2)}MB');
      break;
    }

    // If we're at max attempts, use current result
    if (attempts >= maxAttempts) {
      result = compressed;
      break;
    }

    // Adjust parameters to reach target
    if (compressed.length < targetSizeBytes) {
      // Too small - need to increase size
      if (currentQuality < 95) {
        currentQuality += 5; // Increase quality
      } else {
        currentWidth =
            (currentWidth * 1.3).toInt(); // Increase width significantly
      }
    } else {
      // Too big - need to decrease size
      if (currentQuality > 50) {
        currentQuality -= 5; // Decrease quality
      } else {
        currentWidth = (currentWidth * 0.9).toInt(); // Decrease width
      }
    }

    // Ensure reasonable bounds
    currentQuality = currentQuality.clamp(40, 95);
    currentWidth = currentWidth.clamp(400, 2000);
  }

  print(
      'Final web compression: ${(result.length / 1024 / 1024).toStringAsFixed(2)}MB after $attempts attempts');
  return result;
}

/// Binary search approach to compress mobile image to target size
Future<Uint8List> _compressMobileImageToTargetSize(
    Uint8List imageBytes, int targetSizeBytes, int targetWidth,
    {int? targetHeight}) async {
  int minQuality = 10; // Lowest acceptable quality
  int maxQuality = 90; // Highest quality
  int currentQuality = 70; // Start with a reasonable default

  Uint8List result = imageBytes;
  int attempts = 0;
  final int maxAttempts = 8; // Limit attempts to prevent infinite loops

  // Also decrease resolution if image is very large
  int adjustedWidth = targetWidth;
  if (imageBytes.length > 1 * 1024 * 1024) {
    // > 1MB
    adjustedWidth = (targetWidth * 0.7).toInt(); // 70% of original target width
  } else if (imageBytes.length > 3 * 1024 * 1024) {
    // > 3MB
    adjustedWidth = (targetWidth * 0.5).toInt(); // 50% of original target width
  }

  // Binary search for the right quality level
  while (attempts < maxAttempts) {
    attempts++;

    // Compress with current quality
    Uint8List compressed = await FlutterImageCompress.compressWithList(
      imageBytes,
      quality: currentQuality,
      minWidth: adjustedWidth,
      minHeight: targetHeight ?? 0,
    );

    // Check resulting size
    int sizeDiff = compressed.length - targetSizeBytes;
    double sizeMB = compressed.length / (1024 * 1024);

    print(
        'Mobile compression attempt $attempts: Quality=$currentQuality, Size=${sizeMB.toStringAsFixed(2)}MB, Target=${(targetSizeBytes / 1024 / 1024).toStringAsFixed(2)}MB, Diff=${(sizeDiff / 1024 / 1024).toStringAsFixed(2)}MB');

    // If we're within 5% of target size or have reached max attempts, return this result
    if (attempts >= maxAttempts || (sizeDiff.abs() < 0.05 * targetSizeBytes)) {
      result = compressed;
      break;
    }

    // Adjust quality based on result
    if (compressed.length > targetSizeBytes) {
      // Too big, decrease quality
      maxQuality = currentQuality;
      currentQuality = (minQuality + maxQuality) ~/ 2;
    } else {
      // Too small, increase quality
      minQuality = currentQuality;
      currentQuality = (minQuality + maxQuality) ~/ 2;
    }
  }

  print(
      'Final mobile compression: ${(result.length / 1024 / 1024).toStringAsFixed(2)}MB with quality ~$currentQuality after $attempts attempts');
  return result;
}
