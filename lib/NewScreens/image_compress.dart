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
  int minQuality = 30; // Higher minimum quality
  int maxQuality = 95; // Higher maximum quality
  int currentQuality = 80; // Start with higher quality

  Uint8List result = imageBytes;
  int attempts = 0;
  final int maxAttempts = 10; // More attempts for better results

  // Don't reduce width as aggressively - we want 700KB, not 69KB!
  int initialWidth = targetWidth;
  if (imageBytes.length > 5 * 1024 * 1024) {
    // Only reduce width for very large images (>5MB)
    initialWidth = (targetWidth * 0.8).toInt(); // 80% instead of 60%
  }

  // Binary search for the right quality level
  while (attempts < maxAttempts) {
    attempts++;

    // Compress with current quality
    Uint8List compressed = await resizeWebImage(imageBytes, initialWidth,
        targetHeight: targetHeight, quality: currentQuality);

    // Check resulting size
    int sizeDiff = compressed.length - targetSizeBytes;
    double sizeMB = compressed.length / (1024 * 1024);

    print(
        'Web compression attempt $attempts: Quality=$currentQuality, Size=${sizeMB.toStringAsFixed(2)}MB, Target=${(targetSizeBytes / 1024 / 1024).toStringAsFixed(2)}MB, Diff=${(sizeDiff / 1024 / 1024).toStringAsFixed(2)}MB');

    // If we're within 10% of target size or have reached max attempts, return this result
    if (attempts >= maxAttempts || (sizeDiff.abs() < 0.1 * targetSizeBytes)) {
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

    // If we're stuck at minimum quality and still too small, try increasing width
    if (currentQuality <= minQuality + 5 &&
        compressed.length < targetSizeBytes * 0.5) {
      initialWidth = (initialWidth * 1.2).toInt(); // Increase width by 20%
      print('Increasing width to $initialWidth to reach target size');
    }
  }

  print(
      'Final web compression: ${(result.length / 1024 / 1024).toStringAsFixed(2)}MB with quality ~$currentQuality after $attempts attempts');
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
