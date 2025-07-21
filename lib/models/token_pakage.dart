class TokenPackage {
  final String id;
  final String name;
  final int tokens;
  final double price;

  TokenPackage({
    required this.id,
    required this.name,
    required this.tokens,
    required this.price,
  });

  factory TokenPackage.fromJson(Map<String, dynamic> json) {
    return TokenPackage(
      id: json['id'] as String,
      name: json['name'] as String,
      tokens: json['tokens'] as int,
      price: json['price'] as double,
    );
  }
}

// Dummy data for now, ideally fetched from your backend
List<TokenPackage> availableTokenPackages = [
  TokenPackage(id: 'package_100', name: '100 Tokens', tokens: 100, price: 50.0),
  TokenPackage(
    id: 'package_500',
    name: '500 Tokens',
    tokens: 500,
    price: 200.0,
  ),
  TokenPackage(
    id: 'package_1000',
    name: '1000 Tokens',
    tokens: 1000,
    price: 400.0,
  ),
];
