/// Primitive boundary for v3. Implementations live outside the envelope and
/// manager so algorithm changes cannot leak into transport or persistence.
abstract interface class V3CryptoAdapter {
  Future<List<int>> encrypt({
    required List<int> plaintext,
    required List<int> associatedData,
    required Map<String, dynamic> context,
  });

  Future<List<int>> decrypt({
    required List<int> ciphertext,
    required List<int> associatedData,
    required Map<String, dynamic> context,
  });
}
