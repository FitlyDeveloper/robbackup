import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// For web, we'll use our custom methods
import 'web_impl.dart' if (dart.library.io) 'web_impl_stub.dart';

// Only import the package on mobile platforms
import 'package:flutter_image_compress/flutter_image_compress.dart'
    if (dart.library.html) 'web_image_compress_stub.dart';

/// Compress an image to a target file size of 0.7MB (727,040 bytes)
/// Images smaller than 0.7MB will be left untouched
/// For web, this uses canvas resize
/// For mobile, this uses flutter_image_compress with quality adjustments
Future<Uint8List> compressImage(
  Uint8List imageBytes, {
  int quality = 85,
  int targetWidth = 1200,
  int? targetHeight,
}) async {
  if (imageBytes.isEmpty) {
    return Uint8List(0);
  }

  // Exact target size in bytes (0.7MB)
  final int targetSizeBytes = 727040; // 0.7 * 1024 * 1024 = 727,040 bytes
  
  // If image is already smaller than 0.7MB, return it unchanged
  if (imageBytes.length <= targetSizeBytes) {
    print('Image already below 0.7MB (${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)}MB), skipping compression');
    return imageBytes;
  }

  try {
    if (kIsWeb) {
      // Web implementation - use binary search to reach target size
      return await _compressWebImageToTargetSize(
        imageBytes, 
        targetSizeBytes,
        targetWidth,
        targetHeight: targetHeight,
      );
    } else {
      // Mobile implementation - use binary search to reach target size
      return await _compressMobileImageToTargetSize(
        imageBytes, 
        targetSizeBytes,
        targetWidth,
        targetHeight: targetHeight,
      );
    }
  } catch (e) {
    print('Error compressing image: $e');
    // Return original bytes as fallback
    return imageBytes;
  }
}

/// Binary search approach to compress web image to target size
Future<Uint8List> _compressWebImageToTargetSize(
  Uint8List imageBytes,
  int targetSizeBytes,
  int targetWidth,
  {int? targetHeight}
) async {
  int minQuality = 10;  // Lowest acceptable quality
  int maxQuality = 95;  // Highest quality
  int currentQuality = 85;  // Start with a reasonable default
  
  Uint8List result = imageBytes;
  int attempts = 0;
  final int maxAttempts = 8;  // Limit attempts to prevent infinite loops
  
  // Binary search for the right quality level
  while (attempts < maxAttempts) {
    attempts++;
    
    // Compress with current quality
    Uint8List compressed = await resizeWebImage(
      imageBytes, 
      targetWidth,
      targetHeight: targetHeight, 
      quality: currentQuality
    );
    
    // Check resulting size
    int sizeDiff = compressed.length - targetSizeBytes;
    double sizeMB = compressed.length / (1024 * 1024);
    
    print('Web compression attempt $attempts: Quality=$currentQuality, Size=${sizeMB.toStringAsFixed(2)}MB, Target=${(targetSizeBytes/1024/1024).toStringAsFixed(2)}MB, Diff=${(sizeDiff/1024/1024).toStringAsFixed(2)}MB');
    
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
  
  print('Final web compression: ${(result.length / 1024 / 1024).toStringAsFixed(2)}MB with quality ~$currentQuality after $attempts attempts');
  return result;
}

/// Binary search approach to compress mobile image to target size
Future<Uint8List> _compressMobileImageToTargetSize(
  Uint8List imageBytes,
  int targetSizeBytes,
  int targetWidth,
  {int? targetHeight}
) async {
  int minQuality = 10;  // Lowest acceptable quality
  int maxQuality = 95;  // Highest quality
  int currentQuality = 85;  // Start with a reasonable default
  
  Uint8List result = imageBytes;
  int attempts = 0;
  final int maxAttempts = 8;  // Limit attempts to prevent infinite loops
  
  // Also decrease resolution if image is very large
  int adjustedWidth = targetWidth;
  if (imageBytes.length > 3 * 1024 * 1024) {  // > 3MB
    adjustedWidth = (targetWidth * 0.8).toInt();  // 80% of original target width
  } else if (imageBytes.length > 5 * 1024 * 1024) {  // > 5MB
    adjustedWidth = (targetWidth * 0.7).toInt();  // 70% of original target width
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
    
    print('Mobile compression attempt $attempts: Quality=$currentQuality, Size=${sizeMB.toStringAsFixed(2)}MB, Target=${(targetSizeBytes/1024/1024).toStringAsFixed(2)}MB, Diff=${(sizeDiff/1024/1024).toStringAsFixed(2)}MB');
    
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
  
  print('Final mobile compression: ${(result.length / 1024 / 1024).toStringAsFixed(2)}MB with quality ~$currentQuality after $attempts attempts');
  return result;
}
