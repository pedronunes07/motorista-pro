# v27 — comprovantes, rotas e consulta de áreas de atenção

A base é a versão v26 completa, incluindo a correção do teste do PR #20. O workflow agora compila os arquivos versionados do aplicativo; os ZIPs antigos ficam apenas como arquivo histórico e não sobrescrevem o código durante o build.

- Preços com ponto ou vírgula são lidos integralmente. Troco, dinheiro a cobrar, saldo e totais de carteira não são ganhos de uma corrida concluída.
- Conclusões precisam de contexto de comprovante. Campos faltantes ou ambíguos ficam pendentes, sem usar preço ou distância estimados da oferta como dados realizados.
- O histórico grava origem/destino do comprovante; quando disponíveis apenas na oferta explicitamente aceita, identifica essa procedência. Uma oferta apenas visualizada nunca fornece rota para a corrida finalizada.
- OCR/acessibilidade compartilham uma fila durável, com revisão e confirmação somente após a gravação no Flutter. Leituras repetidas não duplicam o registro e uma nova leitura pode completar o mesmo registro.
- Registros antigos continuam disponíveis para conferência. Não entram nos totais confirmados até serem revisados. A tela permite corrigir os campos pelo comprovante.
- O cartão pode consultar um serviço de áreas de atenção com consentimento. Respostas vencidas, sem fonte ou correspondentes a outro endereço não geram alerta. A resposta tardia não altera outra oferta.

## Limites conhecidos

Não foi disponibilizada uma API/base nacional de áreas de risco. A consulta permanece desativada no APK; a infraestrutura e testes estão em `server/`, com instruções de ativação. A IA opcional extrai localidade escrita no endereço e não classifica bairros por suposição. Não há chave secreta nova no aplicativo.

Sem identificação de viagem ou transição observável entre dois comprovantes idênticos, a leitura de tela não consegue distinguir com certeza se houve uma nova corrida; evita duplicar. O app precisa enxergar o comprovante final. Endereços não lidos não podem ser reconstruídos e não há traçado GPS.

Para salvar pelo OCR, a acessibilidade deve confirmar que a janela pertence ao aplicativo de corrida. Reconhecer o nome “99” ou “Uber” numa foto aberta em outro aplicativo não autoriza gravar receita no histórico.

Os testes cobrem leitura, soma, ciclo de ofertas/conclusões, confirmação de salvamento, revisão manual e validação das fontes de alerta. É necessário validar no aparelho os layouts reais da 99/Uber/inDrive, especialmente comprovantes que não mostram rótulos, eventos ou endereços completos.
