import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_compression.dart';

class ProfilePicturePicker extends StatefulWidget {
  final String? currentImageUrl;
  final XFile? selectedImage;
  final Function(XFile) onImageSelected;
  final double size;

  const ProfilePicturePicker({
    Key? key,
    this.currentImageUrl,
    this.selectedImage,
    required this.onImageSelected,
    this.size = 120,
  }) : super(key: key);

  @override
  State<ProfilePicturePicker> createState() => _ProfilePicturePickerState();
}

class _ProfilePicturePickerState extends State<ProfilePicturePicker> {
  bool _isLoading = false;
  File? _tempCompressedFile;

  @override
  void dispose() {
    // Clean up any temporary compressed file when widget is disposed
    _cleanupTempFile();
    super.dispose();
  }

  Future<void> _cleanupTempFile() async {
    if (_tempCompressedFile != null && await _tempCompressedFile!.exists()) {
      try {
        await _tempCompressedFile!.delete();
        print('Cleaned up temp compressed file');
      } catch (e) {
        print('Error cleaning up temp file: $e');
      }
    }
  }

  Future<void> _pickImage() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Clean up previous temp file
      await _cleanupTempFile();
      
      final ImagePicker picker = ImagePicker();
      
      // Pick image with size limit
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048, // Reduced from 4096
        maxHeight: 2048, // Reduced from 4096
        imageQuality: 90, // Slightly reduced quality at picker level
      );

      if (image == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      // Check file size before processing
      final file = File(image.path);
      final fileSize = await file.length();
      print('Picked image size: ${fileSize ~/ 1024}KB');

      // Validate image
      final bool isValid = await ImageCompressionUtil.isValidImage(image, maxSizeMB: 25);
      if (!isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid image or file too large. Please select a different image.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Processing image...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Use the safer compression method
      final File? compressedImage = await ImageCompressionUtil.compressImageSafely(image);
      
      if (compressedImage == null) {
        throw Exception('Failed to compress image');
      }

      // Store reference to temp file for cleanup
      _tempCompressedFile = compressedImage;
      
      // Create XFile from compressed file
      final XFile compressedXFile = XFile(compressedImage.path);

      // Notify parent widget
      widget.onImageSelected(compressedXFile);

      // Dismiss the image picker dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image selected successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Unable to process image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildProfileImage() {
    // Show loading indicator while processing
    if (_isLoading) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (widget.selectedImage != null && widget.selectedImage!.path.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(widget.selectedImage!.path),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder();
          },
        ),
      );
    } else if (widget.currentImageUrl != null && widget.currentImageUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          widget.currentImageUrl!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder();
          },
        ),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        size: widget.size * 0.6,
        color: Colors.grey[600],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProfileImage(),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : _pickImage,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.camera_alt,
                size: 20,
                color: _isLoading ? Colors.grey : null,
              ),
              const SizedBox(width: 8),
              Text(
                widget.selectedImage == null ? 'Select Photo' : 'Change Photo',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        if (!_isLoading && widget.selectedImage == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Tap to select a profile picture',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
      ],
    );
  }
}
