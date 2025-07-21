class Transactions {
  final int? id;
  final String name;
  final double amount;
  final String phoneNumber;
  final DateTime timestamp;
  final bool isSuccess;

  Transactions({
    this.id,
    required this.name,
    required this.amount,
    required this.phoneNumber,
    required this.timestamp,
    required this.isSuccess,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'phoneNumber': phoneNumber,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isSuccess': isSuccess ? 1 : 0,
    };
  }

  factory Transactions.fromMap(Map<String, dynamic> map) {
    return Transactions(
      id: map['id'] as int?,
      name: map['name'] as String,
      amount: map['amount'] as double,
      phoneNumber: map['phoneNumber'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      isSuccess: map['isSuccess'] == 1,
    );
  }
}
