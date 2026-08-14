/// Contrato para persistência e identidade do motorista.
///
/// A implementação Firebase deve ser ativada após executar `flutterfire
/// configure`, que gera as opções específicas de Android e iOS. Manter esse
/// contrato separado evita acoplamento da interface com o provedor de dados.
abstract class FirebaseService {
  Future<void> signInWithEmail(String email, String password);
  Future<void> signOut();
  Future<void> saveTransaction(Map<String, dynamic> transaction);
  Stream<List<Map<String, dynamic>>> transactionsFor(String userId);
}
