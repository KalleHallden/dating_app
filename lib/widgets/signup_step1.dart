import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/image_compression.dart';
import '../providers/signup_provider.dart';

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

  @override
  void initState() {
    super.initState();
    // Initialize with existing data if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SignupProvider>();
      if (provider.name != null) {
        _nameController.text = provider.name!;
      }
      if (provider.birthdate != null) {
        _birthdate = provider.birthdate;
      }
      if (provider.profileImage != null) {
        _image = provider.profileImage;
      }
      setState(() {});
    });
  }

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Processing image...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final compressedFile = await ImageCompressionUtil.compressImageSafely(image);

      if (compressedFile == null) {
        throw Exception('Failed to process image');
      }

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
    ImageCompressionUtil.cleanupTempFiles();
    super.dispose();
  }

  Widget _buildImagePreview() {
    if (_image == null) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[300]!, width: 2),
        ),
        child: Icon(
          Icons.add_a_photo_outlined,
          size: 40,
          color: Colors.grey[500],
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
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Let\'s get started',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'First, tell us a bit about yourself',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'First name',
              hintText: 'Enter your first name',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF985021)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _birthdate ?? DateTime(2000),
                firstDate: DateTime(1900),
                lastDate: DateTime.now().subtract(const Duration(days: 18 * 365)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        primary: const Color(0xFF985021),
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (date != null) setState(() => _birthdate = date);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, color: Colors.grey),
                  const SizedBox(width: 12),
                  Text(
                    _birthdate == null
                        ? 'Select your birthday'
                        : '${_birthdate!.day}/${_birthdate!.month}/${_birthdate!.year}',
                    style: TextStyle(
                      fontSize: 16,
                      color: _birthdate == null ? Colors.grey : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                _buildImagePreview(),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isProcessingImage ? null : _pickImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    foregroundColor: const Color(0xFF985021),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: _isProcessingImage
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF985021)),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Processing...'),
                          ],
                        )
                      : Text(
                          _image == null ? 'Add Profile Picture' : 'Change Picture',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 56,
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
                          missingFields += missingFields.isEmpty ? 'Birthday' : ', Birthday';
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
                backgroundColor: const Color(0xFF985021),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.grey[300],
              ),
              child: const Text(
                'Next',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}