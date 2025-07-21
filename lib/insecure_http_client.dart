import 'dart:io';
import 'package:http/io_client.dart';

/// Use this client only for development purposes.
/// It disables SSL certificate validation!
IOClient createInsecureHttpClient() {
  final HttpClient httpClient =
      HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;

  return IOClient(httpClient);
}
