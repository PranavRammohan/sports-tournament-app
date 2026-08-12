// signup_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import '../main.dart';
import '../api_client.dart';
import '../utils.dart';
import '../constants/areas.dart';
import '../constants/cities.dart';
import '../validators.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  String? _selectedCity;
  String? _selectedArea;
  String? _selectedGender;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Uint8List? _profileImageBytes;
  String? _profileImageBase64;

  Future<void> _pickProfileImage() async {
    try {
      final picked = await pickProfileImageAsDataUri();
      if (picked == null) return;
      setState(() {
        _profileImageBytes = picked.bytes;
        _profileImageBase64 = picked.dataUri;
      });
    } on ProfileImageTooLargeException {
      _showAlert(
        'Photo too large',
        'That photo is too large — please pick a smaller one.',
      );
    }
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phoneNumber = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (_selectedCity == null) {
      _showAlert('Missing city', 'Please select your city.');
      return;
    }
    if (_selectedArea == null) {
      _showAlert('Missing area', 'Please select your area.');
      return;
    }
    if (_selectedGender == null) {
      _showAlert('Missing gender', 'Please select your gender.');
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await ApiClient.post(
        '/auth/signup',
        body: {
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'phoneNumber': phoneNumber,
          'password': password,
          'confirmPassword': confirmPassword,
          'city': _selectedCity,
          'area': _selectedArea,
          'gender': _selectedGender,
          'profilePicUrl': _profileImageBase64,
        },
      );

      if (res.statusCode != 201) {
        _showAlert('Signup failed', res.errorOr('Something went wrong.'));
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('authToken', res.data['token']);
      await prefs.setString('user', jsonEncode(res.data['user']));

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtleTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    final avatarBg = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final avatarIconColor = isDark
        ? Colors.grey.shade500
        : Colors.grey.shade400;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Form(
            key: _formKey,
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
                'Play. Compete. Rank. Let\'s set up your profile.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // Profile picture picker (optional)
              Center(
                child: GestureDetector(
                  onTap: _pickProfileImage,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: avatarBg,
                        backgroundImage: _profileImageBytes != null
                            ? MemoryImage(_profileImageBytes!)
                            : null,
                        child: _profileImageBytes == null
                            ? Icon(
                                Icons.person,
                                size: 44,
                                color: avatarIconColor,
                              )
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
                child: Text(
                  'Add a profile photo (optional)',
                  style: TextStyle(fontSize: 12, color: subtleTextColor),
                ),
              ),

              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      validator: (v) =>
                          requiredField(v, label: 'First name'),
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
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                validator: passwordValidator,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                validator: (v) => confirmPasswordValidator(
                  v,
                  _passwordController.text,
                ),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    tooltip: _obscureConfirmPassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
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
              DropdownButtonFormField<String>(
                initialValue: _selectedCity,
                decoration: const InputDecoration(
                  labelText: 'City',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                isExpanded: true,
                hint: const Text('Select your city'),
                items: indianCities
                    .map(
                      (city) =>
                          DropdownMenuItem(value: city, child: Text(city)),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _selectedCity = value;
                  // The area list is scoped to the chosen city — a
                  // previously picked area from a different city wouldn't
                  // be a valid option once the city changes.
                  _selectedArea = null;
                }),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _selectedArea,
                decoration: const InputDecoration(
                  labelText: 'Area',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
                isExpanded: true,
                hint: const Text('Select your area'),
                items: (areasByCity[_selectedCity] ?? [])
                    .map(
                      (area) =>
                          DropdownMenuItem(value: area, child: Text(area)),
                    )
                    .toList(),
                onChanged: _selectedCity == null
                    ? null
                    : (value) => setState(() => _selectedArea = value),
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
