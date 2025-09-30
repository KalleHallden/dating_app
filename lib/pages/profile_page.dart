import 'dart:io';
import 'package:kora/widgets/signout_button.dart';
import 'package:kora/widgets/profile_picture_picker.dart';
import 'package:kora/widgets/location_picker.dart';
import 'package:kora/models/UserLocation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/location_service.dart';
import '../services/account_deletion_service.dart';
import '../utils/age_calculator.dart';
import '../utils/gender_preference_converter.dart';
import 'welcome_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMessage;
  XFile? _selectedImage;
  bool _isUploadingImage = false;
  supabase.RealtimeChannel? _realtimeChannel;
  String? _locationCity; // Add this to store the city name
  String? _editLocationCity; // Add this for edit mode city name
  
  // Add a key to force rebuild of profile image
  Key _profileImageKey = UniqueKey();
  
  // Edit mode state
  bool _isEditMode = false;
  
  // Edit mode controllers
  late TextEditingController _nameController;
  late TextEditingController _aboutMeController;
  String? _editGender;
  String? _editGenderPreference;
  UserLocation? _editLocation;
  int _editMinAge = 18;
  int _editMaxAge = 100;
  XFile? _editProfileImage;
  bool _isSaving = false;
  DateTime? _editDateOfBirth;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _aboutMeController = TextEditingController();
    _loadUserProfile();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    // Clean up the real-time subscription
    _realtimeChannel?.unsubscribe();
    _nameController.dispose();
    _aboutMeController.dispose();
    super.dispose();
  }

  Future<void> _setupRealtimeSubscription() async {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;

    if (currentUser == null) {
      print('No authenticated user for real-time subscription');
      return;
    }

    // Create a unique channel name
    final channelName = 'profile-updates-${currentUser.id}-${DateTime.now().millisecondsSinceEpoch}';

    // Subscribe to changes in the users table for the current user
    _realtimeChannel = client
        .channel(channelName)
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: supabase.PostgresChangeFilter(
            type: supabase.PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUser.id,
          ),
          callback: (payload) {
            print('Received real-time update: $payload');
            // Update the UI with the new profile data
            if (mounted && !_isEditMode) {
              setState(() {
                _userData = {
                  ...?_userData,
                  ...payload.newRecord,
                };
                // Force rebuild of profile image by changing key
                _profileImageKey = UniqueKey();
              });
              // Reload location city if location changed
              _loadLocationCity();
            }
          },
        )
        .subscribe();

    print('Subscribed to real-time updates on channel: $channelName');
  }

  Future<void> _loadUserProfile() async {
    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;
      
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      final response = await client
          .from('users')
          .select()
          .eq('user_id', currentUser.id)
          .single();

      setState(() {
        _userData = response;
        _isLoading = false;
        // Initialize edit mode values
        _initializeEditValues();
      });
      
      // Load location city name
      await _loadLocationCity();
    } catch (e) {
      print('Error loading user profile: $e');
      setState(() {
        _errorMessage = 'Failed to load profile: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLocationCity() async {
    if (_userData == null) return;
    
    final location = _userData!['location'];
    if (location != null) {
      final cityName = await LocationService().getCityFromPostGISPoint(location);
      if (mounted) {
        setState(() {
          _locationCity = cityName;
        });
      }
    }
  }

  Future<void> _loadEditLocationCity() async {
    if (_editLocation == null) return;
    
    final cityName = await LocationService().getCityFromCoordinates(
      _editLocation!.lat,
      _editLocation!.long,
    );
    
    if (mounted) {
      setState(() {
        _editLocationCity = cityName;
      });
    }
  }

  void _initializeEditValues() {
    if (_userData == null) return;
    
    _nameController.text = _userData!['name'] ?? '';
    _aboutMeController.text = _userData!['about_me'] ?? '';
    _editGender = _userData!['gender'];
    // Convert gender preference from backend format to frontend format for editing
    _editGenderPreference = GenderPreferenceConverter.backendToFrontend(_userData!['gender_preference']);
    
    // Parse age preference
    final agePref = _userData!['age_preference'];
    if (agePref != null && agePref is Map) {
      _editMinAge = agePref['min'] ?? 18;
      _editMaxAge = agePref['max'] ?? 100;
    }
    
    // Parse location
    final location = _userData!['location'];
    if (location != null && location is String) {
      final coords = location.replaceAll('(', '').replaceAll(')', '').split(',');
      if (coords.length == 2) {
        final lat = double.tryParse(coords[0]);
        final long = double.tryParse(coords[1]);
        if (lat != null && long != null) {
          _editLocation = UserLocation(lat: lat, long: long);
        }
      }
    }
    
    // Set edit location city to current location city
    _editLocationCity = _locationCity;

    // Parse date of birth
    final dateOfBirthValue = _userData!['date_of_birth'];
    _editDateOfBirth = AgeCalculator.parseBirthDate(dateOfBirthValue);
  }

  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      _editProfileImage = null;
      _initializeEditValues();
    });
  }

  void _cancelEditMode() {
    setState(() {
      _isEditMode = false;
      _editProfileImage = null;
      _selectedImage = null;
      _editLocationCity = null;
      // Reset values
      _initializeEditValues();
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;
      
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Prepare update data
      final Map<String, dynamic> updateData = {
        'name': _nameController.text.trim(),
        'about_me': _aboutMeController.text.trim(),
        'gender': _editGender,
        // Convert gender preference from frontend format back to backend format
        'gender_preference': GenderPreferenceConverter.frontendToBackend(_editGenderPreference),
        'age_preference': {
          'min': _editMinAge,
          'max': _editMaxAge,
        },
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Add location if changed
      if (_editLocation != null) {
        updateData['location'] = '(${_editLocation!.lat},${_editLocation!.long})';
      }

      // Add date of birth if changed
      if (_editDateOfBirth != null) {
        updateData['date_of_birth'] = _editDateOfBirth!.toIso8601String();
      }

      // Upload new profile picture if selected
      if (_editProfileImage != null) {
        final profilePictureUrl = await _uploadProfilePicture(_editProfileImage!);
        updateData['profile_picture'] = profilePictureUrl;
        updateData['profile_picture_url'] = profilePictureUrl;
      }

      // Update user record
      await client
          .from('users')
          .update(updateData)
          .eq('user_id', currentUser.id);

      // Update local data
      setState(() {
        _userData = {
          ...?_userData,
          ...updateData,
        };
        _isEditMode = false;
        _editProfileImage = null;
        _selectedImage = null;
        _editLocationCity = null;
        // Force rebuild of profile image
        _profileImageKey = UniqueKey();
      });
      
      // Reload location city if location was updated
      if (_editLocation != null) {
        await _loadLocationCity();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickImageForEdit() async {
    try {
      final ImagePicker picker = ImagePicker();
      
      // Pick image directly without using ProfilePicturePicker widget
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );

      if (image == null) return;

      // Update state with the new image
      if (mounted) {
        setState(() {
          _editProfileImage = image;
          _profileImageKey = UniqueKey();
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error selecting image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditProfilePictureDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => true,
          child: Dialog(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Update Profile Picture',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Show current or selected image
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[300],
                      image: _getEditProfileImageDecoration(),
                    ),
                    child: _getEditProfileImageChild(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Close dialog first
                      Navigator.of(dialogContext).pop();
                      // Then pick image
                      await _pickImageForEdit();
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_editProfileImage == null ? 'Select Photo' : 'Change Photo'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  DecorationImage? _getEditProfileImageDecoration() {
    if (_editProfileImage != null) {
      return DecorationImage(
        image: FileImage(File(_editProfileImage!.path)),
        fit: BoxFit.cover,
      );
    }
    
    final profilePictureUrl = _userData?['profile_picture_url'] ?? _userData?['profile_picture'];
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return DecorationImage(
        image: NetworkImage(profilePictureUrl),
        fit: BoxFit.cover,
      );
    }
    
    return null;
  }

  Widget? _getEditProfileImageChild() {
    if (_editProfileImage == null) {
      final profilePictureUrl = _userData?['profile_picture_url'] ?? _userData?['profile_picture'];
      if (profilePictureUrl == null || profilePictureUrl.isEmpty) {
        return const Icon(
          Icons.person,
          size: 60,
          color: Colors.grey,
        );
      }
    }
    return null;
  }

  Future<void> _handleImmediateImageSelected(XFile image) async {
    setState(() {
      _selectedImage = image;
      _isUploadingImage = true;
    });

    try {
      final profilePictureUrl = await _uploadProfilePicture(image);
      
      // Update local data immediately
      if (mounted) {
        setState(() {
          _userData = {
            ...?_userData,
            'profile_picture': profilePictureUrl,
            'profile_picture_url': profilePictureUrl,
          };
          _selectedImage = null;
          _isUploadingImage = false;
          // Force rebuild of profile image
          _profileImageKey = UniqueKey();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error uploading profile picture: $e');
      if (mounted) {
        setState(() {
          _selectedImage = null;
          _isUploadingImage = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload profile picture: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> _uploadProfilePicture(XFile image) async {
    try {
      final client = SupabaseClient.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Convert XFile to File for Supabase upload
      final file = File(image.path);

      // Upload to Supabase Storage
      final storagePath = '${user.id}.jpg';
      print('Uploading profile picture to: $storagePath');

      // Upload the compressed image
      await client.storage.from('profilepicture').upload(
        storagePath,
        file,
        fileOptions: const supabase.FileOptions(
          upsert: true, // Replace existing file
          contentType: 'image/jpeg',
        ),
      );

      // Get the public URL with a timestamp to force refresh
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final profilePictureUrl = '${client.storage.from('profilepicture').getPublicUrl(storagePath)}?t=$timestamp';

      print('Profile picture uploaded successfully! URL: $profilePictureUrl');

      // Only update database if not in edit mode (edit mode updates on save)
      if (!_isEditMode) {
        await client
            .from('users')
            .update({
              'profile_picture': profilePictureUrl,
              'profile_picture_url': profilePictureUrl,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', user.id);
      }

      return profilePictureUrl;
    } catch (e) {
      print('Error uploading profile picture: $e');
      throw e;
    }
  }

  Widget _buildProfileImage() {
    final profilePictureUrl = _userData?['profile_picture_url'] ?? 
                             _userData?['profile_picture'];
    
    // Determine which image to show
    final imageToShow = _isEditMode && _editProfileImage != null 
        ? _editProfileImage 
        : _selectedImage;
    
    return Stack(
      key: _profileImageKey, // Force rebuild when key changes
      children: [
        AspectRatio(
          aspectRatio: 4 / 5, // Instagram portrait format
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[300],
              image: (imageToShow != null && imageToShow.path.isNotEmpty)
                  ? DecorationImage(
                      image: FileImage(File(imageToShow.path)),
                      fit: BoxFit.cover,
                    )
                  : (profilePictureUrl != null && profilePictureUrl.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(profilePictureUrl),
                          fit: BoxFit.cover,
                          onError: (exception, stackTrace) {
                            print('Error loading profile picture: $exception');
                          },
                        )
                      : null,
            ),
            child: (imageToShow == null || imageToShow.path.isEmpty) && 
                   (profilePictureUrl == null || profilePictureUrl.isEmpty)
                ? const Center(
                    child: Icon(
                      Icons.person,
                      size: 100,
                      color: Colors.grey,
                    ),
                  )
                : null,
          ),
        ),
        // Overlay for loading state
        if (_isUploadingImage)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
        // Edit mode profile picture button
        if (_isEditMode)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: Center(
                child: TextButton(
                  onPressed: _isUploadingImage ? null : _showEditProfilePictureDialog,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('Update Profile Picture'),
                ),
              ),
            ),
          ),
        // View mode edit button - removed as per requirements
      ],
    );
  }

  Widget _buildProfileInfo() {
    final name = _userData?['name'] ?? 'Unknown';
    // Calculate age from date of birth
    final dateOfBirthValue = _userData?['date_of_birth'];
    final birthDate = AgeCalculator.parseBirthDate(dateOfBirthValue);
    final age = birthDate != null ? AgeCalculator.calculateAge(birthDate) : 0;
    final aboutMe = _userData?['about_me'] ?? 'No description provided';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and Age with Edit button
          Row(
            children: [
              Expanded(
                child: _isEditMode
                    ? TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Text(
                        '$name, $age',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              if (!_isEditMode)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _enterEditMode,
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Age/Date of Birth Section (only in edit mode)
          if (_isEditMode) ...[
            InkWell(
              onTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: _editDateOfBirth ?? DateTime(2000),
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)), // Must be at least 18
                  helpText: 'Select your date of birth',
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xFF985021),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  setState(() {
                    _editDateOfBirth = picked;
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date of Birth',
                  hintText: 'Select date',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_editDateOfBirth != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF985021).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Age ${AgeCalculator.calculateAge(_editDateOfBirth!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF985021),
                            ),
                          ),
                        )
                      else
                        const Icon(Icons.calendar_today, size: 20),
                    ],
                  ),
                ),
                child: Text(
                  _editDateOfBirth != null
                      ? '${_getMonthName(_editDateOfBirth!.month)} ${_editDateOfBirth!.day}, ${_editDateOfBirth!.year}'
                      : '',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // About Me Section
          const Text(
            'About Me',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          _isEditMode
              ? TextField(
                  controller: _aboutMeController,
                  decoration: InputDecoration(
                    hintText: 'Tell us about yourself...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  maxLines: 4,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                  ),
                )
              : Text(
                  aboutMe,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
          const SizedBox(height: 30),
          
          // Location Section
          _isEditMode
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        print('Opening LocationPicker with current location: ${_editLocation?.lat}, ${_editLocation?.long}');
                        
                        // Navigate to LocationPicker and wait for result
                        final UserLocation? result = await Navigator.push<UserLocation>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LocationPicker(
                              initialLocation: _editLocation,
                              onLocationSelected: null, // We're using return value instead
                            ),
                          ),
                        );
                        
                        // Handle the returned location
                        if (result != null) {
                          print('Received location from picker: ${result.lat}, ${result.long}');
                          
                          setState(() {
                            _editLocation = result;
                            _editLocationCity = null; // Clear city name while loading
                          });
                          
                          // Load the city name for the new location
                          await _loadEditLocationCity();
                          
                          print('Updated edit location to: ${_editLocation?.lat}, ${_editLocation?.long}');
                          print('Updated edit location city to: $_editLocationCity');
                        } else {
                          print('No location returned from picker');
                        }
                      },
                      icon: const Icon(Icons.location_on),
                      label: Text(
                        _editLocation != null
                            ? _editLocationCity ?? 'Location set (${_editLocation!.lat.toStringAsFixed(2)}, ${_editLocation!.long.toStringAsFixed(2)})'
                            : 'Set Location',
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                )
              : _buildInfoRow(Icons.location_on, _locationCity ?? 'Loading...'),
          
          if (!_isEditMode) const SizedBox(height: 12),
          
          // Looking For Section
          _isEditMode
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Looking For',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Gender preference dropdown
                    DropdownButtonFormField<String>(
                      value: _editGenderPreference,
                      decoration: InputDecoration(
                        labelText: 'Gender Preference',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: GenderPreferenceConverter.getFrontendOptions()
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (value) => setState(() => _editGenderPreference = value),
                    ),
                    const SizedBox(height: 16),
                    // Age range
                    const Text(
                      'Age Range',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'Min Age',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(text: _editMinAge.toString()),
                            onChanged: (value) {
                              final age = int.tryParse(value);
                              if (age != null && age >= 18 && age <= 100) {
                                setState(() => _editMinAge = age);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'Max Age',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(text: _editMaxAge.toString()),
                            onChanged: (value) {
                              final age = int.tryParse(value);
                              if (age != null && age >= 18 && age <= 100) {
                                setState(() => _editMaxAge = age);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Gender dropdown
                    DropdownButtonFormField<String>(
                      value: _editGender,
                      decoration: InputDecoration(
                        labelText: 'Your Gender',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: ['Man', 'Woman', 'Other']
                          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (value) => setState(() => _editGender = value),
                    ),
                  ],
                )
              : _buildInfoRow(Icons.favorite, _formatPreferences()),
          
          const SizedBox(height: 30),
          
          // Edit mode buttons
          if (_isEditMode)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : _cancelEditMode,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            )
          else ...[
            // Sign Out Button
            Center(
              child: SignoutButton(
                text: 'Sign Out',
                showIcon: true,
                backgroundColor: Colors.red,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            // Delete Account Button
            Center(
              child: OutlinedButton.icon(
                onPressed: _showDeleteAccountDialog,
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text(
                  'Delete Account',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  String _formatLocation() {
    // This method is now replaced by _locationCity which is loaded asynchronously
    return _locationCity ?? 'Loading...';
  }

  String _formatPreferences() {
    final gender = _userData?['gender'] ?? 'Not specified';
    // Convert gender preference from backend format to frontend format for display
    final genderPref = GenderPreferenceConverter.backendToFrontend(_userData?['gender_preference']);
    final agePref = _userData?['age_preference'];

    String prefString = 'Looking for: $genderPref';

    if (agePref != null && agePref is Map) {
      final minAge = agePref['min'] ?? 18;
      final maxAge = agePref['max'] ?? 100;
      prefString += ', Ages $minAge-$maxAge';
    }

    return prefString;
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  Future<void> _showDeleteAccountDialog() async {
    final TextEditingController reasonController = TextEditingController();
    bool isDeleting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text('Delete Account'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Are you sure you want to delete your account?',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⚠️ Important:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text('• All your data will be permanently deleted'),
                          Text('• Your matches and messages will be removed'),
                          Text('• You may not be able to create a new account immediately'),
                          Text('• There may be a cooldown period before you can register again'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Optional: Tell us why you\'re leaving',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        hintText: 'Your feedback helps us improve...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      maxLines: 3,
                      enabled: !isDeleting,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting
                      ? null
                      : () {
                          reasonController.dispose();
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          // Show second confirmation
                          final bool? confirmed = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text('Final Confirmation'),
                                content: const Text(
                                  'This action cannot be undone. Are you absolutely sure you want to delete your account?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('No, keep my account'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Yes, delete my account'),
                                  ),
                                ],
                              );
                            },
                          );

                          if (confirmed == true) {
                            setDialogState(() {
                              isDeleting = true;
                            });

                            // Call the deletion service
                            final result = await AccountDeletionService().deleteAccount(
                              reason: reasonController.text.trim().isNotEmpty
                                  ? reasonController.text.trim()
                                  : null,
                            );

                            if (!mounted) return;

                            if (result.success) {
                              // Show success message with cooldown info
                              await showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    icon: const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 48,
                                    ),
                                    title: const Text('Account Deleted'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(result.message ?? 'Your account has been successfully deleted.'),
                                        if (result.cooldownDays != null) ...[
                                          const SizedBox(height: 16),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              result.getCooldownMessage(),
                                              style: const TextStyle(fontSize: 14),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                        if (result.canReregisterAfter != null) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            'Available from: ${result.getReregisterDateFormatted()}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    actions: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          // Sign out and navigate to welcome screen
                                          await AccountDeletionService().signOutAfterDeletion();
                                          if (mounted) {
                                            Navigator.of(context).pushAndRemoveUntil(
                                              MaterialPageRoute(
                                                builder: (context) => const WelcomeScreen(),
                                              ),
                                              (route) => false,
                                            );
                                          }
                                        },
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            } else {
                              // Handle error
                              Navigator.of(dialogContext).pop();

                              String errorTitle = 'Deletion Failed';
                              IconData errorIcon = Icons.error_outline;
                              Color errorColor = Colors.red;

                              if (result.isAlreadyDeleted) {
                                errorTitle = 'Account Already Deleted';
                                errorIcon = Icons.info_outline;
                                errorColor = Colors.orange;
                              }

                              await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    icon: Icon(
                                      errorIcon,
                                      color: errorColor,
                                      size: 48,
                                    ),
                                    title: Text(errorTitle),
                                    content: Text(
                                      result.error ?? 'Failed to delete account. Please try again.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            }

                            reasonController.dispose();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: isDeleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Delete Account'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadUserProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Profile' : 'My Profile'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        leading: _isEditMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _isSaving ? null : _cancelEditMode,
              )
            : null,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileImage(),
            _buildProfileInfo(),
          ],
        ),
      ),
    );
  }
}
