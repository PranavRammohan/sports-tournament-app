// Unit tests for validators.dart — the reusable TextFormField validators
// added as part of the "form validation" mobile UI sweep (this app had zero
// TextFormField/validator usage anywhere before this batch).
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/validators.dart';

void main() {
  group('requiredField', () {
    test('rejects null and empty/whitespace strings', () {
      expect(requiredField(null), isNotNull);
      expect(requiredField(''), isNotNull);
      expect(requiredField('   '), isNotNull);
    });

    test('accepts a non-empty string', () {
      expect(requiredField('Alice'), isNull);
    });

    test('error message includes the given label', () {
      expect(requiredField('', label: 'Guest name'), contains('Guest name'));
    });
  });

  group('emailValidator', () {
    test('rejects empty and malformed addresses', () {
      expect(emailValidator(''), isNotNull);
      expect(emailValidator('not-an-email'), isNotNull);
      expect(emailValidator('missing@domain'), isNotNull);
    });

    test('accepts a well-formed address', () {
      expect(emailValidator('player@example.com'), isNull);
    });
  });

  group('phoneValidator', () {
    test('rejects anything that is not exactly 10 digits', () {
      expect(phoneValidator(''), isNotNull);
      expect(phoneValidator('12345'), isNotNull);
      expect(phoneValidator('12345678901'), isNotNull);
      expect(phoneValidator('abcdefghij'), isNotNull);
    });

    test('accepts a 10-digit number', () {
      expect(phoneValidator('9876543210'), isNull);
    });
  });

  group('passwordValidator', () {
    test('rejects empty and too-short passwords', () {
      expect(passwordValidator(''), isNotNull);
      expect(passwordValidator('abc'), isNotNull);
    });

    test('accepts a password at the minimum length', () {
      expect(passwordValidator('abcdef'), isNull);
    });

    test('respects a custom minLength', () {
      expect(passwordValidator('abcdef', minLength: 8), isNotNull);
      expect(passwordValidator('abcdefgh', minLength: 8), isNull);
    });
  });

  group('confirmPasswordValidator', () {
    test('rejects empty and mismatched confirmation', () {
      expect(confirmPasswordValidator('', 'secret1'), isNotNull);
      expect(confirmPasswordValidator('secret2', 'secret1'), isNotNull);
    });

    test('accepts a matching confirmation', () {
      expect(confirmPasswordValidator('secret1', 'secret1'), isNull);
    });
  });

  group('positiveIntValidator', () {
    test('rejects empty, non-numeric, zero, and negative values', () {
      expect(positiveIntValidator(''), isNotNull);
      expect(positiveIntValidator('abc'), isNotNull);
      expect(positiveIntValidator('0'), isNotNull);
      expect(positiveIntValidator('-5'), isNotNull);
    });

    test('accepts a positive whole number', () {
      expect(positiveIntValidator('16'), isNull);
    });
  });

  group('nonNegativeIntValidator', () {
    test('rejects empty, non-numeric, and negative values', () {
      expect(nonNegativeIntValidator(''), isNotNull);
      expect(nonNegativeIntValidator('abc'), isNotNull);
      expect(nonNegativeIntValidator('-1'), isNotNull);
    });

    test('accepts zero and positive whole numbers', () {
      expect(nonNegativeIntValidator('0'), isNull);
      expect(nonNegativeIntValidator('21'), isNull);
    });
  });

  group('ratingValidator', () {
    test('treats an empty value as valid (optional field)', () {
      expect(ratingValidator(''), isNull);
      expect(ratingValidator(null), isNull);
    });

    test('rejects a non-numeric or negative value', () {
      expect(ratingValidator('abc'), isNotNull);
      expect(ratingValidator('-2.5'), isNotNull);
    });

    test('accepts a valid non-negative number', () {
      expect(ratingValidator('6.5'), isNull);
    });
  });

  group('combine', () {
    test('returns the first failing validator\'s message', () {
      final validator = combine([requiredField, emailValidator]);
      expect(validator(''), requiredField(''));
    });

    test('returns null only when every validator passes', () {
      final validator = combine([requiredField, emailValidator]);
      expect(validator('player@example.com'), isNull);
    });
  });
}
