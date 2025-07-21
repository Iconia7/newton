class UssdDataPlan {
  int? id;
  String planName;
  String ussdCodeTemplate; // e.g., *141*100*PN# or *544*AMOUNT#
  double amount; // The amount associated with this data plan (for matching)
  String
  placeholder; // The placeholder in ussdCodeTemplate, e.g., 'PN' or 'AMOUNT'

  UssdDataPlan({
    this.id,
    required this.planName,
    required this.ussdCodeTemplate,
    required this.amount,
    this.placeholder = 'PN', // Default placeholder
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'planName': planName,
      'ussdCodeTemplate': ussdCodeTemplate,
      'amount': amount,
      'placeholder': placeholder,
    };
  }

  factory UssdDataPlan.fromMap(Map<String, dynamic> map) {
    return UssdDataPlan(
      id: map['id'],
      planName: map['planName'],
      ussdCodeTemplate: map['ussdCodeTemplate'],
      amount: map['amount'],
      placeholder:
          map['placeholder'] ?? 'PN', // Handle old data without placeholder
    );
  }
}
