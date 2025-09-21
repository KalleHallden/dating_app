/// Utility class for age-related calculations
class AgeCalculator {
  /// Calculates age from a date of birth
  /// Returns the age in years as of today
  static int calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;

    // Adjust if birthday hasn't occurred this year yet
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }

    return age;
  }

  /// Calculates age from a date of birth string
  /// Expects format: YYYY-MM-DD
  static int calculateAgeFromString(String birthDateString) {
    try {
      final birthDate = DateTime.parse(birthDateString);
      return calculateAge(birthDate);
    } catch (e) {
      // Return a default age if parsing fails
      return 18;
    }
  }

  /// Formats a DateTime to a readable birth date string
  static String formatBirthDate(DateTime birthDate) {
    return '${birthDate.year}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}';
  }

  /// Parses a birth date from database format
  /// Can handle both DateTime and String formats
  static DateTime? parseBirthDate(dynamic birthDateValue) {
    if (birthDateValue == null) return null;

    if (birthDateValue is DateTime) {
      return birthDateValue;
    }

    if (birthDateValue is String) {
      try {
        return DateTime.parse(birthDateValue);
      } catch (e) {
        return null;
      }
    }

    return null;
  }
}