# Alertas de áreas de atenção — integração pendente

Não há base nacional nem credenciais incluídas. A versão distribuída mantém a consulta desligada e informa que falta conectar uma fonte. Não é correto usar o conhecimento geral de uma IA para atribuir perigo a um bairro. O cliente funciona para qualquer cidade do Brasil **quando o provedor tem cobertura e consegue resolver o endereço sem ambiguidade**.

## Ativação por quem mantém o aplicativo

1. Contratar/autorizar uma fonte com cobertura e atualização verificáveis. Implementar no provedor a geocodificação e comparação de ponto com áreas documentadas. Endereço sem município/UF, truncado, geocodificação ambígua ou fora da cobertura deve retornar `unknown`. Não classificar pelo nome do bairro, renda ou presença presumida de facções.
2. Configurar `RISK_PROVIDER_URL` (HTTPS) e, se necessário, `RISK_PROVIDER_KEY` no servidor. O provedor recebe `{country:"BR",address,localityHint}`. Só aceitar alertas com `status:"alert", country:"BR", matchedAddress, matchQuality:"exact", ambiguous:false, sourceName, sourceUrl, updatedAt, expiresAt` (datas em milissegundos UTC). Dados vencidos, com mais de 30 dias ou sem fonte retornam `unknown`. A fonte pode exigir validade ainda menor; respeitar `expiresAt`.
3. Opcional: configurar `OPENAI_API_KEY` e `OPENAI_MODEL` compatível com Structured Outputs. A IA extrai apenas cidade/UF explicitamente escritas no endereço. Não decide risco e não preenche dados ausentes. Sem chave, a consulta ao provedor continua funcionando. Referência: https://developers.openai.com/api/docs/guides/structured-outputs
4. Executar `node --test server/route-risk.test.mjs` e `node server/route-risk.mjs` (Node 22+). O serviço escuta somente em localhost. Publicar via gateway HTTPS com autenticação, limites de requisições e de gasto, e sem logs de corpos/endereços. **O APK ainda não implementa autenticação de gateway: conectar o token de sessão do usuário no cliente antes de publicar um serviço com cobrança.** Não expor uma chave compartilhada no APK.
5. Configurar `route_risk_endpoint` no XML Android com a URL `/risk` do serviço, compilar e testar. O motorista precisa ativar o consentimento em Calculadora flutuante. Nenhum nome de passageiro, preço ou histórico é enviado. A consulta pode transmitir os dois endereços à IA e à fonte; nunca registrar esses endereços em logs. A chamada da OpenAI usa `store:false`.

O exemplo de teste usa endereços e fontes fictícios, apenas como fixture. Não há dados de risco reais nesses arquivos. Sem resultado, o cartão diz “sem dados”, nunca “seguro”. A resposta só altera o cartão que originou a consulta; resposta tardia não muda outra oferta.

Rota salva no histórico significa endereços de origem/destino lidos no comprovante ou na oferta aceita, com a procedência indicada. O app não grava um traçado GPS e não reconstrói endereços ausentes.
