// lib/utils/image_compression.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageCompressionUtil {
  // Reduced dimensions for better memory efficiency
  static const int MAX_WIDTH = 1080; // Reduced from 1920
  static const int MAX_HEIGHT = 1080; // Reduced from 1920
  static const int PROFILE_QUALITY = 80; // Reduced from 85
  static const int MAX_FILE_SIZE = 1 * 1024 * 1024; // Reduced to 1MB
  
  // Add a static method to clean up temporary files
  static Future<void> cleanupTempFiles() async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final List<FileSystemEntity> files = tempDir.listSync();
      
      for (FileSystemEntity file in files) {
        if (file is File && file.path.contains('compressed_')) {
          try {
            await file.delete();
            print('Deleted temp file: ${file.path}');
          } catch (e) {
            print('Error deleting temp file: $e');
          }
        }
      }
    } catch (e) {
      print('Error cleaning up temp files: $e');
    }
  }

  /// Compress an image from XFile with better memory management
  static Future<File> compressImage(XFile imageFile) async {
    File? tempFile;
    
    try {
      // Clean up old temp files first
      await cleanupTempFiles();
      
      // Read the image file
      final File file = File(imageFile.path);
      
      // Check file size before processing
      final int fileSize = await file.length();
      print('Original image size: ${_formatBytes(fileSize)}');
      
      // If file is already small enough, just copy it
      if (fileSize <= MAX_FILE_SIZE) {
        print('Image already within size limit, copying without compression');
        final Directory tempDir = await getTemporaryDirectory();
        final String fileName = 'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final File targetFile = File(path.join(tempDir.path, fileName));
        return await file.copy(targetFile.path);
      }
      
      // For large files, read and compress in chunks
      Uint8List? compressedBytes;
      
      // First try: compress with original method but with lower quality
      compressedBytes = await _compressImageFile(file, PROFILE_QUALITY);
      
      if (compressedBytes == null) {
        throw Exception('Failed to compress image');
      }
      
      // If still too large, reduce quality further
      int quality = PROFILE_QUALITY;
      int attempts = 0;
      const int maxAttempts = 5;
      
      while (compressedBytes!.length > MAX_FILE_SIZE && 
             quality > 20 && 
             attempts < maxAttempts) {
        quality -= 15;
        attempts++;
        print('File still too large (${_formatBytes(compressedBytes.length)}), '
              'reducing quality to $quality% (attempt $attempts)');
        
        // Clear previous compressed data to free memory
        compressedBytes = null;
        
        // Force garbage collection hint
        await Future.delayed(const Duration(milliseconds: 100));
        
        compressedBytes = await _compressImageFile(file, quality);
        
        if (compressedBytes == null) {
          throw Exception('Failed to compress image at quality $quality');
        }
      }
      
      final originalSize = fileSize;
      print('Compressed image size: ${_formatBytes(compressedBytes.length)} '
            '(${((1 - compressedBytes.length / originalSize) * 100).toStringAsFixed(1)}% reduction)');
      
      // Save compressed image to a temporary file
      final Directory tempDir = await getTemporaryDirectory();
      final String fileName = 'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      tempFile = File(path.join(tempDir.path, fileName));
      
      await tempFile.writeAsBytes(compressedBytes);
      
      // Clear the compressed bytes from memory
      compressedBytes = null;
      
      return tempFile;
      
    } catch (e) {
      // Clean up temp file if created
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      
      print('Error in compressImage: $e');
      throw Exception('Failed to compress image: $e');
    }
  }

  /// Compress image file with better error handling
  static Future<Uint8List?> _compressImageFile(File file, int quality) async {
    try {
      // Use file path compression instead of loading entire file into memory
      final String? targetPath = await _getTempFilePath();
      if (targetPath == null) {
        return null;
      }
      
      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        minWidth: MAX_WIDTH,
        minHeight: MAX_HEIGHT,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
        numberOfRetries: 2, // Add retries
      );
      
      if (result == null) {
        return null;
      }
      
      // Read the compressed file
      final compressedFile = File(result.path);
      final bytes = await compressedFile.readAsBytes();
      
      // Delete the temporary compressed file
      try {
        await compressedFile.delete();
      } catch (_) {}
      
      return bytes;
      
    } catch (e) {
      print('Error in _compressImageFile: $e');
      return null;
    }
  }
  
  /// Get a temporary file path
  static Future<String?> _getTempFilePath() async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String fileName = 'temp_compress_${DateTime.now().millisecondsSinceEpoch}.jpg';
      return path.join(tempDir.path, fileName);
    } catch (e) {
      print('Error getting temp file path: $e');
      return null;
    }
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

  /// Validate image before compression with size check
  static Future<bool> isValidImage(XFile imageFile, {int maxSizeMB = 25}) async {
    try {
      final File file = File(imageFile.path);
      final bool exists = await file.exists();
      if (!exists) {
        print('Image file does not exist');
        return false;
      }

      // Check file size (default max 25MB)
      final int fileSize = await file.length();
      final int maxSize = maxSizeMB * 1024 * 1024;
      
      if (fileSize > maxSize) {
        print('Image too large: ${_formatBytes(fileSize)} (max: ${maxSizeMB}MB)');
        return false;
      }

      // Try to get image properties without loading full image
      final imageProperties = await FlutterImageCompress.compressWithFile(imageFile.path);
      
      if (imageProperties == null) {
        print('Could not read image properties');
        return false;
      }
      
      
      return true;
    } catch (e) {
      print('Image validation error: $e');
      return false;
    }
  }
  
  /// Compress with automatic cleanup
  static Future<File?> compressImageSafely(XFile imageFile) async {
    try {
      // Validate first
      final isValid = await isValidImage(imageFile);
      if (!isValid) {
        return null;
      }
      
      // Compress
      final compressedFile = await compressImage(imageFile);
      
      // Schedule cleanup after a delay
      Future.delayed(const Duration(minutes: 5), () {
        cleanupTempFiles();
      });
      
      return compressedFile;
    } catch (e) {
      print('Safe compression failed: $e');
      // Try cleanup on error
      await cleanupTempFiles();
      return null;
    }
  }
}
