enum NotificationType {
  success,
  failure,
  info;

  String get label {
    switch (this) {
      case NotificationType.success:
        return 'Success';
      case NotificationType.failure:
        return 'Failure';
      case NotificationType.info:
        return 'Info';
    }
  }

  static NotificationType fromString(String value) {
    return NotificationType.values.firstWhere(
      (e) => e.toString().split('.').last == value,
      orElse: () => NotificationType.info,
    );
  }
}

class AppNotification {
  final String title;
  final String message;
  final NotificationType type;
  final Map<String, dynamic>? transactionDetails;

  AppNotification({
    required this.title,
    required this.message,
    this.type = NotificationType.info,
    this.transactionDetails,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: NotificationType.fromString(json['type'] ?? 'info'),
      transactionDetails:
          json['transactionDetails'] != null
              ? Map<String, dynamic>.from(json['transactionDetails'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'message': message,
      'type': type.toString().split('.').last,
      'transactionDetails': transactionDetails,
    };
  }
}
