// edit_profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../utils.dart';
import '../validators.dart';
import 'change_password_screen.dart';
import '../constants/areas.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const EditProfileScreen({super.key, required this.currentUser});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  String? _selectedArea;
  String? _selectedGender;
  bool _loading = false;

  Uint8List? _newProfileImageBytes;
  String? _newProfileImageBase64;
  bool _removeExistingPhoto = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(
      text: widget.currentUser['firstName'] ?? '',
    );
    _lastNameController = TextEditingController(
      text: widget.currentUser['lastName'] ?? '',
    );
    _emailController = TextEditingController(
      text: widget.currentUser['email'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.currentUser['phoneNumber'] ?? '',
    );
    _selectedArea = widget.currentUser['location'];
    _selectedGender = widget.currentUser['gender'];
  }

  String? get _existingPhotoUrl => widget.currentUser['profilePicUrl'];

  Future<void> _pickProfileImage() async {
    HapticFeedback.selectionClick();
    try {
      final picked = await pickProfileImageAsDataUri();
      if (picked == null) return;
      setState(() {
        _newProfileImageBytes = picked.bytes;
        _newProfileImageBase64 = picked.dataUri;
        _removeExistingPhoto = false;
      });
    } on ProfileImageTooLargeException {
      _showAlert(
        'Photo too large',
        'That photo is too large — please pick a smaller one.',
      );
    }
  }

  void _removePhoto() {
    HapticFeedback.lightImpact();
    setState(() {
      _newProfileImageBytes = null;
      _newProfileImageBase64 = null;
      _removeExistingPhoto = true;
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedArea == null || _selectedGender == null) {
      _showAlert('Missing fields', 'Please fill in all fields.');
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phoneNumber = _phoneController.text.trim();

    HapticFeedback.lightImpact();
    setState(() => _loading = true);

    try {
      final body = <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phoneNumber': phoneNumber,
        'area': _selectedArea,
        'gender': _selectedGender,
      };
      if (_newProfileImageBase64 != null) {
        body['profilePicUrl'] = _newProfileImageBase64;
      } else if (_removeExistingPhoto) {
        body['profilePicUrl'] = null;
      }

      final res = await ApiClient.patch('/auth/profile', body: body);

      if (res.statusCode != 200) {
        _showAlert('Something went wrong', res.errorOr('Please try again.'));
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(res.data['user']));

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      _showAlert('Network error', 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarBg = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final avatarIconColor = isDark
        ? Colors.grey.shade500
        : Colors.grey.shade400;

    final hasExistingPhoto =
        _existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty;
    final showRemoveOption =
        !_removeExistingPhoto &&
        (hasExistingPhoto || _newProfileImageBytes != null);

    ImageProvider? avatarImage;
    if (_newProfileImageBytes != null) {
      avatarImage = MemoryImage(_newProfileImageBytes!);
    } else if (!_removeExistingPhoto && hasExistingPhoto) {
      // _existingPhotoUrl is a base64 data: URI, never a real hosted URL —
      // NetworkImage silently failed to decode it on Android/iOS (only
      // "worked" on Flutter Web, which delegates to the browser's native
      // data: URL support). See utils.dart's decodeDataUriImage.
      final bytes = decodeDataUriImage(_existingPhotoUrl!);
      if (bytes != null) avatarImage = MemoryImage(bytes);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickProfileImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: avatarBg,
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? Icon(Icons.person, size: 44, color: avatarIconColor)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _pickProfileImage,
                child: const Text(
                  'Change photo',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            if (showRemoveOption)
              Center(
                child: TextButton(
                  onPressed: _removePhoto,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text(
                    'Remove photo',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    validator: (v) => requiredField(v, label: 'First name'),
                    decoration: const InputDecoration(
                      labelText: 'First Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    validator: (v) => requiredField(v, label: 'Last name'),
                    decoration: const InputDecoration(labelText: 'Last Name'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: emailValidator,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              validator: phoneValidator,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                prefixIcon: Icon(Icons.phone_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 6),
            Text('Gender', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _SelectChip(
                    label: 'Male',
                    selected: _selectedGender == 'M',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedGender = 'M');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SelectChip(
                    label: 'Female',
                    selected: _selectedGender == 'F',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedGender = 'F');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedArea,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Area',
                prefixIcon: Icon(Icons.map_outlined),
              ),
              items: bangaloreAreas
                  .map(
                    (area) => DropdownMenuItem(value: area, child: Text(area)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedArea = value),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.password),
              title: const Text('Change Password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _handleSave,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Save Changes'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBg = Theme.of(context).cardColor;
    final unselectedBorder = isDark
        ? Colors.grey.shade600
        : Colors.grey.shade300;
    final unselectedText = isDark ? Colors.grey.shade300 : Colors.grey.shade700;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.08)
              : unselectedBg,
          border: Border.all(
            color: selected ? AppColors.primary : unselectedBorder,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : unselectedText,
            ),
          ),
        ),
      ),
    );
  }
}
