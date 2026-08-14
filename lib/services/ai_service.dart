/// Interface para o assistente. A chave da IA nunca deve ir no aplicativo.
/// O app deve chamar uma Cloud Function/servidor autenticado, que por sua vez
/// conversa com o provedor de IA.
abstract class AiService {
  Future<String> ask({
    required String question,
    required Map<String, dynamic> financialContext,
  });
}
