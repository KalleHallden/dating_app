import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_compression.dart';

class SignupStep1 extends StatefulWidget {
  final Function(String name, int age, XFile image) onDataCollected;

  const SignupStep1({required this.onDataCollected, super.key});

  @override
  State<SignupStep1> createState() => _SignupStep1State();
}

class _SignupStep1State extends State<SignupStep1> {
  final _nameController = TextEditingController();
  DateTime? _birthdate;
  XFile? _image;
  bool _isProcessingImage = false;

  int _calculateAge(DateTime birthdate) {
    final now = DateTime.now();
    int age = now.year - birthdate.year;
    if (now.month < birthdate.month || (now.month == birthdate.month && now.day < birthdate.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickImage() async {
    setState(() {
      _isProcessingImage = true;
    });

    try {
      final picker = ImagePicker();
      
      // Pick image with initial size constraints
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      
      if (image == null) {
        setState(() {
          _isProcessingImage = false;
        });
        return;
      }

      // Show processing message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Processing image...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Validate and compress the image using the compression service
      final compressedFile = await ImageCompressionUtil.compressImageSafely(image);
      
      if (compressedFile == null) {
        throw Exception('Failed to process image');
      }

      // Create XFile from compressed file
      final compressedXFile = XFile(compressedFile.path);
      
      setState(() {
        _image = compressedXFile;
        _isProcessingImage = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image selected successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('Error picking/compressing image: $e');
      setState(() {
        _isProcessingImage = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    // Clean up temporary files when disposing
    ImageCompressionUtil.cleanupTempFiles();
    super.dispose();
  }

  Widget _buildImagePreview() {
    if (_image == null) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person,
          size: 60,
          color: Colors.grey[600],
        ),
      );
    }

    return ClipOval(
      child: Image.file(
        File(_image!.path),
        width: 120,
        height: 120,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error,
              size: 60,
              color: Colors.red[300],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: Text(_birthdate == null
                ? 'Select Birthdate'
                : _birthdate!.toString().split(' ')[0]),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) setState(() => _birthdate = date);
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                _buildImagePreview(),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isProcessingImage ? null : _pickImage,
                  child: _isProcessingImage
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Processing...'),
                          ],
                        )
                      : Text(_image == null ? 'Add Profile Picture' : 'Change Picture'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: ElevatedButton(
              onPressed: _isProcessingImage
                  ? null
                  : () {
                      if (_nameController.text.isNotEmpty && 
                          _birthdate != null && 
                          _image != null) {
                        widget.onDataCollected(
                          _nameController.text,
                          _calculateAge(_birthdate!),
                          _image!,
                        );
                      } else {
                        String missingFields = '';
                        if (_nameController.text.isEmpty) missingFields = 'Name';
                        if (_birthdate == null) {
                          missingFields += missingFields.isEmpty ? 'Birthdate' : ', Birthdate';
                        }
                        if (_image == null) {
                          missingFields += missingFields.isEmpty ? 'Profile Picture' : ', Profile Picture';
                        }
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please provide: $missingFields'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(120, 48),
              ),
              child: const Text('Next'),
            ),
          ),
        ],
      ),
    );
  }
}
