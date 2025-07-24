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

  Future<void> _pickImage() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 100,
      );

      if (image == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final bool isValid = await ImageCompressionUtil.isValidImage(image);
      if (!isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid image file. Please select a different image.'),
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
            content: Text('Compressing image...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final File compressedImage = await ImageCompressionUtil.compressImage(image);
      final XFile compressedXFile = XFile(compressedImage.path);

      widget.onImageSelected(compressedXFile);

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
            content: Text('Error selecting image: $e'),
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
    if (widget.selectedImage != null && widget.selectedImage!.path.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(widget.selectedImage!.path),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
        ),
      );
    } else if (widget.currentImageUrl != null && widget.currentImageUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          widget.currentImageUrl!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
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
          },
        ),
      );
    }
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit,
                size: 20,
                color: _isLoading ? Colors.grey : null,
              ),
              const SizedBox(width: 8),
              Text(
                widget.selectedImage == null ? 'Pick Profile Picture' : 'Change Picture',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
