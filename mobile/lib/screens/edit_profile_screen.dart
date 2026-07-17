// edit_profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

const String apiUrl = 'http://localhost:3000/api/auth';

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

      final response = await http.patch(
        Uri.parse('$apiUrl/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'username': username,
          'phoneNumber': phoneNumber,
          'location': _selectedArea,
          'gender': _selectedGender,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        _showAlert(
          'Something went wrong',
          data['error'] ?? 'Please try again.',
        );
        return;
      }

      // Update the locally cached user object so the rest of the app
      // (Profile header, etc.) reflects the change immediately.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 24),
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
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.white,
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}
