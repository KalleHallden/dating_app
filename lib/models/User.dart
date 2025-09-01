class User {
  final String userId;
  final String? name;
  final String? email;
  final String? profilePicture;
  final int monthlySecondsUsed;
  final int monthlySecondLimit;
  final int totalLifetimeSeconds;
  
  User({
    required this.userId,
    this.name,
    this.email,
    this.profilePicture,
    required this.monthlySecondsUsed,
    required this.monthlySecondLimit,
    required this.totalLifetimeSeconds,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['user_id'] ?? '',
      name: json['name'],
      email: json['email'],
      profilePicture: json['profile_picture'],
      monthlySecondsUsed: json['monthly_seconds_used'] ?? 0,
      monthlySecondLimit: json['monthly_second_limit'] ?? 0,
      totalLifetimeSeconds: json['total_lifetime_seconds'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'email': email,
      'profile_picture': profilePicture,
      'monthly_seconds_used': monthlySecondsUsed,
      'monthly_second_limit': monthlySecondLimit,
      'total_lifetime_seconds': totalLifetimeSeconds,
    };
  }

  /// Converts seconds to minutes with the rule: if seconds > 30, round up to full minute
  /// Example: 2924 seconds = 48.73 minutes -> display as 49 minutes
  int get remainingMonthlyMinutes {
    final remainingSeconds = monthlySecondLimit - monthlySecondsUsed;
    if (remainingSeconds <= 0) return 0;
    
    return (remainingSeconds / 60).ceil();
  }

  /// Get remaining seconds this month
  int get remainingMonthlySeconds {
    final remaining = monthlySecondLimit - monthlySecondsUsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Check if user has enough minutes for a minimum call (5 minutes = 300 seconds)
  bool get hasMinutesForCall {
    return remainingMonthlySeconds >= 300;
  }
}