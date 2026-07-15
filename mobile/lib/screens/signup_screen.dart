// signup_screen.dart
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
  bool _obscurePassword = true;

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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create Account',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Join the ladder and start competing.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 26),
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
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Gender', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
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
              const SizedBox(height: 18),
              TextField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'City',
                  prefixIcon: const Icon(Icons.location_city_outlined),
                  fillColor: Colors.grey.shade100,
                ),
                controller: TextEditingController(text: 'Bangalore'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedArea,
                decoration: const InputDecoration(
                  labelText: 'Area',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
                isExpanded: true,
                hint: const Text('Select your area'),
                items: bangaloreAreas
                    .map(
                      (area) =>
                          DropdownMenuItem(value: area, child: Text(area)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedArea = value),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _handleSignup,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('Sign Up'),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: const Text('Already have an account? Log in'),
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
