// signup_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _selectedArea;
  String? _selectedGender;
  bool _loading = false;

  Future<void> _handleSignup() async {
    final username = _usernameController.text.trim();
    final phoneNumber = _phoneController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || phoneNumber.isEmpty || password.isEmpty) {
      _showAlert('Missing fields', 'Please fill in all fields.');
      return;
    }
    if (_selectedArea == null) {
      _showAlert('Missing area', 'Please select your area in Bangalore.');
      return;
    }
    if (_selectedGender == null) {
      _showAlert('Missing gender', 'Please select your gender.');
      return;
    }
    if (password.length < 6) {
      _showAlert('Weak password', 'Password must be at least 6 characters.');
      return;
    }
    if (!RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
      _showAlert('Invalid number', 'Enter a valid 10-digit mobile number.');
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'phoneNumber': phoneNumber,
          'password': password,
          'location': _selectedArea,
          'gender': _selectedGender,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 201) {
        _showAlert('Signup failed', data['error'] ?? 'Something went wrong.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('authToken', data['token']);
      await prefs.setString('user', jsonEncode(data['user']));

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/select-sports');
    } catch (err) {
      _showAlert(
        'Network error',
        'Could not reach the server. Check your connection.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Create Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                // Gender selector
                const Text(
                  'Gender',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Male'),
                        value: 'M',
                        groupValue: _selectedGender,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setState(() => _selectedGender = v),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Female'),
                        value: 'F',
                        groupValue: _selectedGender,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setState(() => _selectedGender = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // City fixed to Bangalore
                TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'City',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey.shade200,
                  ),
                  controller: TextEditingController(text: 'Bangalore'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedArea,
                  decoration: const InputDecoration(
                    labelText: 'Area',
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  hint: const Text('Select your area'),
                  items: bangaloreAreas
                      .map(
                        (area) =>
                            DropdownMenuItem(value: area, child: Text(area)),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedArea = value);
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _handleSignup,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Sign Up', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/login'),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
