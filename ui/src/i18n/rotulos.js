/**
 * Tradução pt-BR de valores que NÃO são texto fixo da interface.
 *
 * Existem dois casos que não dá para traduzir editando o JSX:
 *
 *   1. Valores gravados no MongoDB e devolvidos pelas APIs
 *      (account_type, loan_type, type de transação...). O `value` dos
 *      <option> continua em inglês de propósito: é ele que vai para o
 *      backend. Aqui traduzimos apenas na hora de EXIBIR.
 *
 *   2. Mensagens de erro/sucesso que os serviços devolvem e a UI mostra
 *      cruas via `err?.data?.message`.
 *
 * Nada aqui altera o que é gravado no banco nem o contrato das APIs.
 */

// --- valores vindos do backend ---------------------------------------------

export const tiposDeConta = {
  Checking: "Conta Corrente",
  Savings: "Poupança",
  Investment: "Investimento",
  "Money Market": "Fundo DI",
};

export const tiposDeEmprestimo = {
  BaseCamp: "Acampamento Base",
  Rover: "Rover",
  PotatoFarming: "Plantação de Batatas",
  IceHome: "Casa de Gelo",
  Rocket: "Foguete",
};

// O repo original usa grafias diferentes por tela ("AadharCard" no cadastro de
// conta, "Aadhar Card" no empréstimo). Mantemos as duas: os `value` enviados ao
// backend continuam exatamente como estavam.
export const tiposDeDocumento = {
  Passport: "Passaporte",
  DriverLicense: "CNH",
  "Driver License": "CNH",
  AadharCard: "CPF",
  "Aadhar Card": "CPF",
};

export const tiposDeTransacao = {
  debit: "débito",
  credit: "crédito",
};

// --- mensagens devolvidas pelos serviços ------------------------------------

export const mensagensApi = {
  // customer-auth (Node)
  "Invalid email or password": "E-mail ou senha inválidos",
  "Email and password are required": "Informe o e-mail e a senha",
  "Name, email and password are required": "Informe o nome, o e-mail e a senha",
  "User already exists": "Este usuário já está cadastrado",
  "User not found": "Usuário não encontrado",
  "Invalid user data": "Dados de usuário inválidos",
  "No JWT cookie found": "Sessão não encontrada. Faça login novamente",
  "Logged out successfully": "Sessão encerrada",

  // atm-locator (Node)
  "ATM not found": "Caixa eletrônico não encontrado",
  "ATM information not found": "Informações do caixa eletrônico não encontradas",
  "Could not create ATM": "Não foi possível cadastrar o caixa eletrônico",
  "No results found": "Nenhum resultado encontrado",

  // serviços Python (accounts / transactions / loan)
  "Insufficient Balance": "Saldo insuficiente",
  "Sender Account Not Found.": "Conta de origem não encontrada.",
  "Receiver Account Not Found.": "Conta de destino não encontrada.",
  "Email or Account number not found.": "E-mail ou número da conta não encontrado.",
  "Transaction is Successful.": "Transferência realizada com sucesso.",
};

// --- helpers ----------------------------------------------------------------

/**
 * Traduz um valor usando um dos mapas acima.
 * Se o valor não estiver no mapa, devolve o original - assim, se o backend
 * mudar, a tela degrada para o inglês em vez de ficar em branco.
 */
export const traduzir = (valor, mapa) => mapa?.[valor] ?? valor;

/** Traduz a mensagem que veio da API, com fallback para o texto original. */
export const traduzirMensagem = (mensagem) =>
  mensagensApi[mensagem] ?? mensagem ?? "Ocorreu um erro inesperado";

/** Data ISO (2026-09-16) -> 16/09/2026 */
export const formatarData = (iso) => {
  if (!iso) return "";
  const [ano, mes, dia] = String(iso).substring(0, 10).split("-");
  return dia && mes && ano ? `${dia}/${mes}/${ano}` : iso;
};
