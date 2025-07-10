import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  int _calculateAge(DateTime birthdate) {
    final now = DateTime.now();
    int age = now.year - birthdate.year;
    if (now.month < birthdate.month || (now.month == birthdate.month && now.day < birthdate.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _image = image);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _pickImage,
            child: Text(_image == null ? 'Add Profile Picture' : 'Picture Added'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_nameController.text.isNotEmpty && _birthdate != null && _image != null) {
                widget.onDataCollected(
                  _nameController.text,
                  _calculateAge(_birthdate!),
                  _image!,
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All fields are required')),
                );
              }
            },
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
