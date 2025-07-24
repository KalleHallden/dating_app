// lib/utils/image_compression.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageCompressionUtil {
  // Target dimensions for different use cases
  static const int MAX_WIDTH = 1920; // Full HD width
  static const int MAX_HEIGHT = 1920; // Full HD height
  static const int PROFILE_QUALITY = 85; // 85% quality for good balance
  static const int MAX_FILE_SIZE = 2 * 1024 * 1024; // 2MB max

  /// Compress an image from XFile (used by image_picker)
  static Future<File> compressImage(XFile imageFile) async {
    // Read the image file
    final File file = File(imageFile.path);
    final Uint8List? imageBytes = await file.readAsBytes();
    
    if (imageBytes == null) {
      throw Exception('Failed to read image file');
    }

    // Get the original file size
    final int originalSize = imageBytes.length;
    print('Original image size: ${_formatBytes(originalSize)}');

    // Compress the image
    Uint8List? compressedBytes = await _compressImageBytes(
      imageBytes,
      file.path,
    );

    if (compressedBytes == null) {
      throw Exception('Failed to compress image');
    }

    // If still too large, reduce quality further
    int quality = PROFILE_QUALITY;
    while (compressedBytes!.length > MAX_FILE_SIZE && quality > 20) {
      quality -= 10;
      print('File still too large (${_formatBytes(compressedBytes.length)}), reducing quality to $quality%');
      
      compressedBytes = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: MAX_WIDTH,
        minHeight: MAX_HEIGHT,
        quality: quality,
        format: CompressFormat.jpeg,
      );
    }

    print('Compressed image size: ${_formatBytes(compressedBytes.length)} (${((1 - compressedBytes.length / originalSize) * 100).toStringAsFixed(1)}% reduction)');

    // Save compressed image to a temporary file
    final Directory tempDir = await getTemporaryDirectory();
    final String fileName = 'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final File compressedFile = File(path.join(tempDir.path, fileName));
    
    await compressedFile.writeAsBytes(compressedBytes);
    
    return compressedFile;
  }

  /// Compress image bytes with automatic format detection
  static Future<Uint8List?> _compressImageBytes(
    Uint8List imageBytes,
    String filePath,
  ) async {
    // Determine format from file extension
    final String extension = path.extension(filePath).toLowerCase();
    CompressFormat format = CompressFormat.jpeg;
    
    if (extension == '.png') {
      format = CompressFormat.png;
    } else if (extension == '.webp') {
      format = CompressFormat.webp;
    }

    // Compress with maintaining aspect ratio
    return await FlutterImageCompress.compressWithList(
      imageBytes,
      minWidth: MAX_WIDTH,
      minHeight: MAX_HEIGHT,
      quality: PROFILE_QUALITY,
      format: format,
      // This maintains aspect ratio - it will fit within MAX_WIDTH x MAX_HEIGHT
      // without stretching the image
      keepExif: false, // Remove EXIF data to save space
    );
  }

  /// Format bytes to human readable format
  static String _formatBytes(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = 0;
    double value = bytes.toDouble();
    
    while (value >= 1024 && i < suffixes.length - 1) {
      value /= 1024;
      i++;
    }
    
    return "${value.toStringAsFixed(decimals)} ${suffixes[i]}";
  }

  /// Validate image before compression
  static Future<bool> isValidImage(XFile imageFile) async {
    try {
      final File file = File(imageFile.path);
      final bool exists = await file.exists();
      if (!exists) return false;

      // Check file size (reject if > 50MB to prevent memory issues)
      final int fileSize = await file.length();
      if (fileSize > 50 * 1024 * 1024) {
        print('Image too large: ${_formatBytes(fileSize)}');
        return false;
      }

      // Check if it's actually an image by trying to decode it
      final Uint8List bytes = await file.readAsBytes();
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1,
        minHeight: 1,
        quality: 1,
      );
      
      return result != null;
    } catch (e) {
      print('Image validation error: $e');
      return false;
    }
  }
}
