# Consultas DQL do LAB 3

> **Valide numa execução a seco.** Estas consultas não foram rodadas contra um
> tenant. A sintaxe do DQL é estável, mas os **nomes de métrica** (`dt.service.*`)
> e os atributos disponíveis dependem da versão do tenant e de o OneAgent estar
> em full-stack. Rode cada uma no **Notebooks** antes de levá-las ao dashboard —
> o Notebook mostra o erro e sugere o campo correto; o tile do dashboard só
> aparece vazio.
>
> Atalho: o **Assist** (`Cmd+I`) escreve DQL a partir de pergunta em português.
> Vale usá-lo em aula como contraponto ao MCP + LLM que vocês montaram na aula 2.

---

## 1. Equivalências diretas com a aula 2

Para a tabela de comparação entre as três ferramentas.

### Taxa de chamadas por serviço
Equivale a `traces_span_metrics_calls_total` no Prometheus.

```
timeseries chamadas = sum(dt.service.request.count),
  by: { dt.entity.service },
  filter: in(dt.entity.service, entitySelector("type(SERVICE),toRelationship.isServiceOf(type(CLOUD_APPLICATION_NAMESPACE),entityName(\"fiap-bank\"))"))
```

### Latência p90 do `transactions`
Equivale ao painel de p90 do dashboard `1 - Saúde do Negócio`.

```
timeseries p90 = percentile(dt.service.request.response_time, 90),
  by: { dt.entity.service },
  filter: entityName(dt.entity.service) == "transactions"
```

### Logs de erro do namespace
Equivale ao Drilldown → Logs com `service_name = transaction`.

```
fetch logs
| filter k8s.namespace.name == "fiap-bank"
| filter loglevel == "ERROR"
| sort timestamp desc
| fields timestamp, k8s.container.name, content
```

### As transações do log, com valor
A mesma pergunta que vocês fizeram ao LLM na aula 2
(*"mostre o valor de cada transação"*), agora em consulta.

```
fetch logs
| filter k8s.namespace.name == "fiap-bank"
| filter k8s.container.name == "transactions"
| parse content, "LD:resto ' amount: ' DOUBLE:valor"
| filter isNotNull(valor)
| fields timestamp, valor, content
| sort timestamp desc
```

---

## 2. O que a aula 2 não conseguiu fazer

### Latência separada por versão durante o canary
Durante `caos.sh canary 20`, mostra v1 e v2 lado a lado. **Este é o tile que
justifica o canary**: sem ele a média esconde a degradação de 20% dos usuários.

```
timeseries p90 = percentile(dt.service.request.response_time, 90),
  by: { dt.entity.service, span.version }
| filter entityName(dt.entity.service) == "transactions"
```

> Se `span.version` não existir no seu tenant, o atributo pode estar como
> `service.version` ou vir do `metadataEnrichment` como `k8s.pod.label.version`.
> Descubra com: `fetch spans | filter k8s.namespace.name == "fiap-bank" | fields keys()`

### Erro que veio do sidecar e não da aplicação
O discriminador do game day: um 503 do Envoy **não** tem span de aplicação
filho. Se esta consulta retorna linhas e o log do pod está limpo, a falha está
na malha.

```
fetch spans
| filter k8s.namespace.name == "fiap-bank"
| filter request.is_failed == true
| summarize chamadas = count(), by: { span.name, k8s.container.name }
| sort chamadas desc
```

---

## 3. Dashboard executivo

Quatro tiles. A regra: se um tile não muda nenhuma decisão, ele sai.

| Tile | Consulta | Decisão que suporta |
|---|---|---|
| Transferências por minuto | `timeseries sum(dt.service.request.count), filter: entityName(dt.entity.service)=="transactions"` | o negócio está fluindo? |
| Jornadas com erro | `fetch spans \| filter request.is_failed==true \| summarize count(), by:{span.name}` | qual jornada priorizar |
| Orçamento de erro restante | tile de SLO (app Service-Level Objectives) | pausar deploy ou não |
| Previsão de saturação | tile `davis forecast` sobre CPU/memória do namespace | agir antes do impacto |

O quarto é o que não existia na aula 2 — e é o bloco de observabilidade
preditiva da ementa.

---

## 4. Notebook de postmortem

Estrutura sugerida, alternando markdown e consulta:

1. **O que aconteceu** — texto do aluno, em linguagem de negócio
2. **Quando começou** — `fetch events | filter event.kind == "DAVIS_PROBLEM"`
3. **Quantos clientes** — contagem de sessões/requisições afetadas na janela
4. **Quanto custou** — volume transacionado perdido × ticket médio
5. **Como foi detectado** — Davis sozinho? em quantos minutos?
6. **O que muda estruturalmente** — a parte que vale nota

O entregável da aula é este notebook preenchido, não um print.
