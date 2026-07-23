// edit_profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../main.dart';
import '../config.dart';
import 'change_password_screen.dart';

const List<String> bangaloreAreas = [
  'Koramangala',
  'Indiranagar',
  'HSR Layout',
  'BTM Layout',
  'Jayanagar',
  'JP Nagar',
  'Whitefield',
  'Marathahalli',
  'Electronic City',
  'Bellandur',
  'Sarjapur Road',
  'Hebbal',
  'Yelahanka',
  'Malleshwaram',
  'Rajajinagar',
  'Basavanagudi',
  'Banashankari',
  'RT Nagar',
  'Frazer Town',
  'Ulsoor',
  'MG Road',
  'Domlur',
  'CV Raman Nagar',
  'Kalyan Nagar',
  'Banaswadi',
  'Vijayanagar',
  'Rajarajeshwari Nagar',
  'Kengeri',
  'Yeshwanthpur',
  'Nagarbhavi',
  'Hennur',
  'Bannerghatta Road',
  'KR Puram',
  'Mahadevapura',
  'Uttarahalli',
  'Kanakapura Road',
  'Konanakunte',
  'Anjanapura',
  'Padmanabhanagar',
  'Girinagar',
  'Kumaraswamy Layout',
  'Vasanthapura',
  'Chikkalasandra',
  'Hulimavu',
  'Bommanahalli',
  'Begur',
  'Arekere',
  'Gottigere',
  'Silk Board',
  'Madiwala',
  'Bilekahalli',
  'Kudlu',
];

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const EditProfileScreen({super.key, required this.currentUser});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _usernameController;
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
    _usernameController = TextEditingController(
      text: widget.currentUser['username'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.currentUser['phoneNumber'] ?? '',
    );
    _selectedArea = widget.currentUser['location'];
    _selectedGender = widget.currentUser['gender'];
  }

  String? get _existingPhotoUrl => widget.currentUser['profilePicUrl'];

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 70,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _newProfileImageBytes = bytes;
      _newProfileImageBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _removeExistingPhoto = false;
    });
  }

  void _removePhoto() {
    setState(() {
      _newProfileImageBytes = null;
      _newProfileImageBase64 = null;
      _removeExistingPhoto = true;
    });
  }

  Future<void> _handleSave() async {
    final username = _usernameController.text.trim();
    final phoneNumber = _phoneController.text.trim();

    if (username.isEmpty ||
        phoneNumber.isEmpty ||
        _selectedArea == null ||
        _selectedGender == null) {
      _showAlert('Missing fields', 'Please fill in all fields.');
      return;
    }
    if (!RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
      _showAlert('Invalid number', 'Enter a valid 10-digit mobile number.');
      return;
    }

    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final body = <String, dynamic>{
        'username': username,
        'phoneNumber': phoneNumber,
        'location': _selectedArea,
        'gender': _selectedGender,
      };
      if (_newProfileImageBase64 != null) {
        body['profilePicUrl'] = _newProfileImageBase64;
      } else if (_removeExistingPhoto) {
        body['profilePicUrl'] = null;
      }

      final response = await http.patch(
        Uri.parse('$baseApiUrl/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        _showAlert(
          'Something went wrong',
          data['error'] ?? 'Please try again.',
        );
        return;
      }

      await prefs.setString('user', jsonEncode(data['user']));

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
      avatarImage = NetworkImage(_existingPhotoUrl!);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
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
                    onTap: () => setState(() => _selectedGender = 'M'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SelectChip(
                    label: 'Female',
                    selected: _selectedGender == 'F',
                    onTap: () => setState(() => _selectedGender = 'F'),
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
