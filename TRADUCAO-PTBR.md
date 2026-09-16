# Interface em português do Brasil

A UI do fork foi traduzida para pt-BR e a marca passou a ser **FIAP OTEL Bank**.
O objetivo é que, ao subir os containers, fique evidente que se trata da
aplicação modificada — e não do demo original da Cisco.

## A regra que mantém o backend intacto

O texto visível vem de **três origens diferentes**, e só uma delas dá para
traduzir editando JSX:

| Origem | Exemplo | Onde foi tratado |
|---|---|---|
| Texto fixo no JSX | botões, labels, placeholders, textos legais | editado direto nos `.jsx` |
| Valor gravado no MongoDB | `account_type: "Checking"` | `src/i18n/rotulos.js` (mapa de exibição) |
| Mensagem devolvida pela API | `"Invalid email or password"` | `src/i18n/rotulos.js` (dicionário) |

**Nenhum `value=` de `<option>` foi alterado.** O rótulo virou português, mas o
valor enviado ao backend continua o mesmo:

```jsx
<option value="AadharCard">CPF</option>
```

Assim o modelo de dados, os serviços Python e os serviços Node seguem
exatamente como estavam — nada de rebuild de backend, nada de migração.

> Curiosidade que justifica a abordagem: o repo original já era inconsistente
> aqui — a mesma opção aparece como `value="AadharCard"` na abertura de conta e
> `value="Aadhar Card"` no empréstimo. O mapa em `rotulos.js` cobre as duas
> grafias de propósito.

## `src/i18n/rotulos.js`

Um módulo só, sem dependência nova (nada de `react-i18next`):

- `tiposDeConta`, `tiposDeEmprestimo`, `tiposDeDocumento`, `tiposDeTransacao` —
  tradução de valores vindos do banco.
- `mensagensApi` — tradução das mensagens de erro/sucesso dos serviços.
- `traduzir(valor, mapa)` e `traduzirMensagem(msg)` — sempre com **fallback para
  o texto original**. Se o backend mudar uma mensagem, a tela mostra o inglês em
  vez de quebrar ou ficar vazia.
- `formatarData(iso)` — `2026-09-16` vira `16/09/2026` no extrato.

As mensagens da API são traduzidas nos 10 pontos onde a UI exibia
`err?.data?.message` cru. Sem isso, o erro de login — provavelmente a primeira
coisa que um aluno vê ao errar a senha — continuaria em inglês.

## Glossário

Conta Corrente · Poupança · Investimento · Fundo DI · Transferência · Extrato ·
Empréstimo · Saldo disponível · Taxa de juros · Prazo · Conta de origem /
Conta de destino · débito / crédito · Documento · CPF · CNH · Caixas Eletrônicos ·
Aberto / Fechado · CEP

Tipos de empréstimo mantêm o tom marciano do demo: Acampamento Base · Rover ·
Plantação de Batatas · Casa de Gelo · Foguete.

## Ligação com a observabilidade

`index.html` agora tem `lang="pt-BR"` e o título
`FIAP OTEL Bank — Demo de Observabilidade`. O título da página **aparece no
Splunk RUM**, então a modificação fica visível também na telemetria, não só na
tela.

## O que foi validado

Rodando a stack local (mongo + customer-auth + dashboard + accounts + ui) e
navegando no browser:

| Item | Resultado |
|---|---|
| `vite build` com o código traduzido | ✅ |
| Home, login, cadastro e busca de caixas em pt-BR | ✅ |
| Login real → menu, cartão de conta e rodapé em pt-BR | ✅ |
| Conta gravada no Mongo continua `account_type: "Checking"` | ✅ modelo intacto |
| Cartão exibe **CONTA CORRENTE** | ✅ via mapa |
| Login com senha errada exibe **"E-mail ou senha inválidos"** | ✅ backend respondeu em inglês e o dicionário traduziu |

Dois bugs foram encontrados e corrigidos justamente por rodar a aplicação:

1. **"CONTA CONTA CORRENTE"** — o JSX tinha o prefixo literal `Conta ` e o mapa
   já devolvia "Conta Corrente". O prefixo foi removido.
2. **`otel-rum-entrypoint.sh` derrubava o container** quando o `index.html`
   estava bind-montado: `mv` falha com *Resource busy* sobre bind mount. Agora
   o arquivo é escrito no lugar (`cat >`), o que funciona nos dois casos.
