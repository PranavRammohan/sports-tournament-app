// validators.dart
// Reusable TextFormField validators — GAP (deferred mobile UI item) "form
// validation." Before this, every screen either validated imperatively
// (`if (x.isEmpty) setState(() => _error = ...)`) or just let the backend's
// 400 response be the first sign something was wrong, with no inline
// per-field error text anywhere. These are small, composable functions
// matching the `String? Function(String?)` shape TextFormField.validator
// expects, so a field can chain a few with [combine].

String? requiredField(String? value, {String label = 'This field'}) {
  if (value == null || value.trim().isEmpty) {
    return '$label is required.';
  }
  return null;
}

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? emailValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Email is required.';
  }
  if (!_emailPattern.hasMatch(value.trim())) {
    return 'Enter a valid email address.';
  }
  return null;
}

final RegExp _tenDigitPhone = RegExp(r'^\d{10}$');

String? phoneValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Mobile number is required.';
  }
  if (!_tenDigitPhone.hasMatch(value.trim())) {
    return 'Enter a valid 10-digit mobile number.';
  }
  return null;
}

String? passwordValidator(String? value, {int minLength = 6}) {
  if (value == null || value.isEmpty) {
    return 'Password is required.';
  }
  if (value.length < minLength) {
    return 'Password must be at least $minLength characters.';
  }
  return null;
}

// Not a validator itself — a helper for the common "confirm password
// matches" case, called from the confirm field with the original password.
String? confirmPasswordValidator(String? value, String original) {
  if (value == null || value.isEmpty) {
    return 'Please confirm your password.';
  }
  if (value != original) {
    return 'Passwords do not match.';
  }
  return null;
}

String? positiveIntValidator(String? value, {String label = 'This value'}) {
  if (value == null || value.trim().isEmpty) {
    return '$label is required.';
  }
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed < 1) {
    return '$label must be a whole number of at least 1.';
  }
  return null;
}

String? nonNegativeIntValidator(String? value, {String label = 'This value'}) {
  if (value == null || value.trim().isEmpty) {
    return '$label is required.';
  }
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed < 0) {
    return '$label must be 0 or more.';
  }
  return null;
}

String? ratingValidator(String? value, {String label = 'Rating'}) {
  if (value == null || value.trim().isEmpty) return null; // optional field
  final parsed = double.tryParse(value.trim());
  if (parsed == null || parsed < 0) {
    return '$label must be a valid non-negative number.';
  }
  return null;
}

// Chains multiple validators, returning the first non-null error — lets a
// field require both "not empty" and "looks like a code" without writing a
// bespoke closure per screen.
String? Function(String?) combine(List<String? Function(String?)> validators) {
  return (value) {
    for (final validator in validators) {
      final result = validator(value);
      if (result != null) return result;
    }
    return null;
  };
}
