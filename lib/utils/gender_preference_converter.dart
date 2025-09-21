/// Utility class for converting between frontend and backend gender preference formats
class GenderPreferenceConverter {
  /// Convert from backend format (singular) to frontend format (plural) for display
  static String backendToFrontend(String? backendValue) {
    if (backendValue == null) return 'Everyone';

    switch (backendValue.toLowerCase()) {
      case 'man':
        return 'Men';
      case 'woman':
        return 'Women';
      case 'men':
        return 'Men'; // Already in correct format
      case 'women':
        return 'Women'; // Already in correct format
      case 'everyone':
      case 'man or woman':
        return 'Everyone';
      case 'non-binary':
        return 'Non-binary';
      case 'other':
        return 'Other';
      default:
        return 'Everyone';
    }
  }

  /// Convert from frontend format (plural) to backend format (singular) for storage
  static String frontendToBackend(String? frontendValue) {
    if (frontendValue == null) return 'everyone';

    switch (frontendValue.toLowerCase()) {
      case 'men':
        return 'man';
      case 'women':
        return 'woman';
      case 'everyone':
      case 'man or woman':
        return 'everyone';
      case 'non-binary':
        return 'non-binary';
      case 'other':
        return 'other';
      default:
        return 'everyone';
    }
  }

  /// Get the list of available frontend options for dropdowns
  static List<String> getFrontendOptions() {
    return ['Men', 'Women', 'Everyone', 'Non-binary'];
  }

  /// Get the list of available backend options (for validation)
  static List<String> getBackendOptions() {
    return ['man', 'woman', 'everyone', 'non-binary', 'other'];
  }
}