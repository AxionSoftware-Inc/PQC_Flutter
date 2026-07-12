class ChatEncryptionException implements Exception {
  ChatEncryptionException(this.message);

  final String message;

  @override
  String toString() => message;
}
