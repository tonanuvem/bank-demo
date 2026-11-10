# Telas do Dynatrace, uma a uma

Mapa dos `[PRINT: ...]` do `k8s/README.md` para a navegação real, com o que
cada tela exige para ter dado dentro.

> **A regra que organiza tudo:** as telas de AIOps não são *encontradas*, são
> **preparadas**. O card do Davis aparece sozinho, mas SLO, detector de
> anomalia, Guardian e Workflow precisam existir **antes** do caos — um SLO
> criado depois não tem o que queimar, e um detector criado depois não tem
> linha de base. A seção 4 lista o que montar antes do bloco 4 do roteiro.

---

## 1. Agora, sem caos nenhum — a instalação está viva?

| O que ver | Onde | Sinal de que está certo |
|---|---|---|
| O cluster | **Kubernetes** → Explorer → Clusters | o cluster aparece com nós e namespaces contados |
| Os nós | **Kubernetes** → Explorer → Nodes | `master`, `node1..3` com CPU e memória |
| O namespace | **Kubernetes** → Explorer → Namespaces | `fiap-bank` na lista |
| Os workloads | **Kubernetes** → Explorer → Workloads | `ui`, `dashboard`, `accounts`, `transactions-v1/v2`, `customer-auth`, `atm-locator`, `mongodb`, `stress-carga` |
| A topologia | **Smartscape** → Kubernetes overview | `K8S_NAMESPACE` com `fiap-bank` entre eles |
| Os serviços | **Services** | os processos aparecem como serviços próprios, não só como pods |

> **Contadores zerados no topo não são erro.** O Explorer respeita o seletor de
> tempo (`Last 30 minutes`). Logo depois da instalação, o resumo pode mostrar
> `Nodes 0` enquanto a aba Nodes já lista os quatro. Aumente para `Last 2
> hours` e eles aparecem.

Se **Services** estiver vazio mas os pods aparecerem, o OneAgent está vendo a
infraestrutura e não os processos: é o caso de conferir
`kubectl -n dynatrace get dynakube -o yaml` e o `cloudNativeFullStack`.

---

## 2. Os PRINTs do roteiro

| PRINT do README | Navegação | Depende de |
|---|---|---|
| Clusters, com aviso de *monitoring issues* | **Kubernetes** → Explorer → Clusters | ter os dois clusters (EKS do professor + kubeadm) no mesmo tenant |
| Workload `transactions` com `istio-proxy` | **Kubernetes** → Explorer → Workloads → `transactions-v1` → Containers | sidecar injetado |
| Smartscape: aplicação → serviço → processo → host | **Smartscape** → Service dependency graph, começando em `transactions` | OneAgent nos processos |
| Service flow da jornada | **Distributed Tracing** → filtro `k8s.namespace.name = fiap-bank` → um trace → **Service flow** | carga rodando |
| SLO da jornada | **Service-Level Objectives** → o SLO que você criar (seção 4) | criado antes |
| SLO de latência queimando, disponibilidade verde | mesma tela, durante `caos.sh delay` | SLO + caos |
| Card do Davis com causa raiz | **Problems** → o problema aberto → Root cause | caos + linha de base |
| p90 por versão, v1 e v2 | **Notebooks** ou **Dashboards**, com o DQL de `dql.md` | canary ligado |
| Site Reliability Guardian reprovando a v2 | **Site Reliability Guardian** → execução do guardian | guardian criado antes |
| Workflow disparado pelo problema | **Workflows** → execução | workflow criado antes |

---

## 3. AIOps: o que o Davis faz, em quatro telas

### 3.1 Problems — a única que aparece sozinha

**Problems** → o problema → *Root cause*, *Affected entities*, *Timeline*.

É o centro do bloco 4. O que vale cronometrar é o tempo entre o
`caos.sh abort 503 20` e o card aparecer — e comparar com o tempo que o aluno
levou para achar o mesmo sintoma no Grafana da aula 2.

A pergunta que vale a aula continua a do roteiro: o Davis aponta uma causa;
ele acerta? A falha está no **sidecar**, não no processo, e o log da aplicação
está limpo.

### 3.2 Davis Anomaly Detection — o detector que você escolhe

**Davis Anomaly Detection** → *Create custom event for alerting*, sobre uma
métrica de negócio, não de infraestrutura. A boa candidata aqui é a taxa de
transações: o `delay` derruba o volume sem gerar um único erro, e um detector
sobre contagem percebe o que um detector sobre taxa de erro nunca veria.

Use *auto-adaptive threshold* em vez de limiar fixo — é a diferença entre
"alerta quando passar de X" (aula 2, Prometheus) e "alerta quando sair do
padrão aprendido" (esta aula).

### 3.3 Davis forecast — previsão, no Notebook

**Notebooks** → célula DQL com `timeseries` e a função de previsão do Davis,
projetando a taxa de transações ou o uso de memória dos pods para as próximas
horas. É o que responde "quando isso vira problema?" em vez de "isso já é
problema?".

Para um time de operação de bolsa, a leitura é de capacidade: a projeção
cruza o limite antes ou depois do fim do pregão?

### 3.4 Kubernetes Recommendations — AIOps sem caos nenhum

**Kubernetes** → Recommendations.

Esta tela funciona **hoje**, sem game day, e tem a melhor história desta
montagem: o container da `ui` roda o vite em modo dev e estava com
`limits.memory: 256Mi`. O kernel matava o processo por OOM, o pod reiniciava
e o Envoy respondia `no healthy upstream` — sintoma que aponta para a malha,
causa que estava no cgroup. A aplicação não registrava erro nenhum, porque
quem mata não é a aplicação.

É o exemplo honesto de observabilidade aplicada a custo e estabilidade, e
aconteceu neste laboratório, não num slide.

---

## 4. O que montar ANTES do bloco 4

Nesta ordem, durante os 30–40 minutos de linha de base:

1. **SLO de latência** da jornada de transferência — **Service-Level
   Objectives** → *Create SLO*, sobre o serviço `transactions`. Sem ele, o
   `caos.sh delay` não tem o que queimar, e o contraste com o SLO de
   disponibilidade (que fica verde) é o ponto do bloco.
2. **SLO de disponibilidade** do mesmo serviço — é o par que não queima.
3. **Detector de anomalia** sobre a taxa de transações (3.2).
4. **Site Reliability Guardian** com dois objetivos: taxa de erro e latência
   do `transactions`. É ele que reprova a v2 no bloco 5.
5. **Workflow** disparado por problema do Davis no namespace `fiap-bank`.
   Mesmo que só anote num Notebook, o ponto é mostrar o laço fechado:
   detecção → decisão → ação.

---

## 5. Telas que podem não ter dado — e o que fazer

Honestidade vale mais que uma lista bonita:

| Tela | Por quê | Alternativa |
|---|---|---|
| **Business Flow** | depende de *business events*; a aplicação não emite nenhum por conta própria | derivar de log com OpenPipeline, ou tratar como demonstração conceitual |
| **Experience Vitals / Session Replay** | exige RUM no navegador; a UI é um vite dev server e a injeção automática pode não ocorrer | conferir em **Experience Vitals**; se não houver aplicação web, usar um **Synthetic** no lugar |
| **Synthetic monitoring** | precisa ser criado, e a URL do lab precisa estar acessível de fora | criar um HTTP monitor para `http://IP:30400/` — amarra com o `probe_success` do blackbox exporter da aula 2 |
| **Logs** | chegam via OneAgent; o filtro é por `k8s.namespace.name` | ver `dql.md`, seção 1 |

---

## 6. Assist (Davis CoPilot)

`Cmd+I` abre o Assist em qualquer tela. Vale usar **na frente da turma** para
transformar uma pergunta em DQL — "latência p90 do transactions por versão na
última hora" — e depois comparar com a consulta escrita à mão em `dql.md`.

O interessante pedagogicamente não é ele acertar: é discutir o que você
precisa saber para avaliar se a consulta que ele gerou responde mesmo à
pergunta.

---

## 7. Prioridade: o que e' NOVIDADE e o que e' repeticao

Medido no tenant depois de uma hora de carga. O criterio nao e' "o que o
produto tem", e' **o que as aulas 1 e 2 nao fizeram**.

### 7.0 Antes de tudo: metade da aplicacao esta invisivel em trace

O Distributed Tracing mostra **so' `customer-auth` e `ui`** (~839 e ~132
requisicoes). O Smartscape → Service dependency graph confirma: 2 services e
1 frontend. `dashboard`, `accounts`, `transactions` e `loan` nao aparecem.

Motivo: o code module do OneAgent instrumenta Node automaticamente, e **nao
instrumenta Python**. Nos servicos Python a instrumentacao viria do
OpenTelemetry -- que este laboratorio desliga de proposito
(`OTEL_SDK_DISABLED: "true"` no `00-namespace.yaml`) para nao duplicar com o
OneAgent. Em Node a decisao estava certa; em Python ela apaga tudo.

Nos logs isso nao acontece: o DaemonSet de log monitoring le o stdout de
qualquer container, e os workloads Python sao os que mais logam
(`dashboard` 9K, `transactions-v1` 6K, `accounts` 5K).

**Por que isso e' prioridade e nao detalhe:** o game day degrada o
`transactions`, e a chamada `dashboard -> transactions` e' Python para
Python. Sem instrumentacao, a evidencia central do bloco 4 nao existe em
trace -- sobra log e metrica de Kubernetes.

A correcao e' local, porque o proprio DynaKube ja' subiu um coletor OTLP:

```
kubectl -n dynatrace get svc telemetry-ingest
# 4317/TCP (gRPC) e 4318/TCP (HTTP)
```

Nos Deployments Python (`accounts`, `transactions-v1`, `transactions-v2`,
`loan`, `dashboard`), e **somente neles**:

```yaml
- { name: OTEL_SDK_DISABLED, value: "false" }
- { name: OTEL_EXPORTER_OTLP_ENDPOINT, value: "http://telemetry-ingest.dynatrace:4317" }
```

Nos servicos Node (`customer-auth`, `atm-locator`) **nao** mexa: ali o
OneAgent ja' instrumenta, e ligar o OTel junto duplica o trace.

Isso vira conteudo, nao remendo: as tres aulas se encontram no mesmo ponto --
o agente proprietario cobre as linguagens que ele cobre, e o resto entra por
OpenTelemetry, que e' exatamente o que as aulas 1 e 2 usaram.

#### E por que nao jogar TUDO no OpenTelemetry, inclusive o Node?

E' uma escolha defensavel, nao um erro -- mas tem preco, e o preco e' maior
do que parece.

**Nao basta ligar a variavel.** O code module do OneAgent injeta em processo
Node sempre que esta presente no pod. Ligar o SDK OTel junto coloca dois
agentes no mesmo processo: span duplicado, dois contextos de trace e metrica
inflada. Para ir de OTel puro em Node e' preciso EXCLUIR aqueles pods da
injecao (`dynatrace.com/inject: "false"`), e ai' comeca a lista de perdas.

**O que se perde ao tirar o OneAgent do Node, neste laboratorio:**

- a entidade de frontend que aparece no Smartscape ("My web application")
  existe porque o OneAgent injetou o JavaScript de RUM no HTML servido pelo
  processo Node. Sem ele somem tambem **Experience Vitals** e **Session
  Replay** -- uma das telas previstas no bloco 3;
- visibilidade de codigo (hotspot por metodo) e a ligacao automatica
  processo → container → pod → no' → host no Smartscape;
- a linha de base automatica por endpoint, que e' o insumo do Davis.

**E a razao pedagogica, que e' a mais forte:** a aula 2 ja' foi
OpenTelemetry puro -- Tempo, span metrics no Prometheus, Loki. Se a aula 3
tambem for OTel puro, ela vira a aula 2 com outro backend, e a comparacao
que justifica as tres aulas perde o sentido. A diferenca que vale ensinar e'
justamente: o que o agente proprietario entrega sem ninguem configurar, e o
que o OTel entrega que agente nenhum entrega.

**Quando "tudo via OTel" E' a resposta certa:** quando portabilidade e
capacidade de troca de fornecedor pesam mais que profundidade (preocupacao
legitima numa instituicao financeira); quando a linguagem nao e' coberta
pelo agente; quando voce precisa controlar amostragem e cardinalidade; ou
quando a mesma telemetria precisa alimentar mais de um destino.

O arranjo que ficou no laboratorio tem um ganho que nao estava no plano: os
**dois modelos convivem no mesmo sistema e na mesma tela**. `ui` e
`customer-auth` chegam pelo OneAgent; `dashboard`, `accounts`,
`transactions` e `loan` chegam por OTLP. Da' para comparar os dois caminhos
lado a lado, com a mesma requisicao -- o que nenhuma das duas aulas
anteriores podia fazer.

### 7.1 Novidade de verdade — vale tempo de aula

| Ordem | Tela | Por que e' novo | Pronto hoje? |
|---|---|---|---|
| 1 | **Problems** (Davis) | correlacao e causa raiz sem ninguem escrever regra. Nas aulas 1 e 2 todo alerta foi configurado a mao | so' com o caos |
| 2 | **Site Reliability Guardian** | nao e' painel, e' **decisao**: aprova ou reprova uma versao. Nenhuma aula anterior teve um portao automatico | sim |
| 3 | **Workflows** | fecha o laco: problema → acao. Observabilidade que *faz*, nao so' mostra | sim |
| 4 | **Anomaly Detection** | limiar que se adapta ao padrao aprendido, contra o limiar fixo do Prometheus | sim |

### 7.2 Novidade parcial — um minuto cada, de passagem

- **Logs**: a faceta `k8s.workload.name` ja' vem com a contagem por workload
  sem ninguem ter definido indice, label ou schema. O contraste com os labels
  do Loki e os indices do Splunk se faz numa tela so'.
- **Smartscape**: topologia descoberta sozinha. O Tempo da aula 2 ja' dava um
  service graph; o que muda aqui e' descer ate' processo e host.

### 7.3 Repeticao — comprima ou corte

SLO (feito duas vezes), Dashboards (feito no Grafana), cascata de trace
(feita com Tempo e com o APM do Splunk), busca de log (feita no Splunk e no
Loki). Mostrar de novo gasta o tempo que falta nas quatro telas de cima.

### 7.4 O fio de AIOps que amarra a aula

**Detectar → decidir → agir.** As aulas 1 e 2 pararam em *ver*.

1. **Detectar**: o Davis abre o problema sozinho (Problems)
2. **Decidir**: o Guardian reprova a v2 contra objetivos escritos (SRG)
3. **Agir**: o Workflow anota o pod, abre o ticket, dispara o rollback

Se a aula couber em uma unica demonstracao, e' essa sequencia -- e ela so'
funciona se Guardian e Workflow existirem **antes** do caos.

### 7.5 Dois avisos vindos das telas

- O app **Anomaly Detection** mostra o banner *"moved to Settings. The
  current will be deprecated by the end of the year"*. Monte o detector pela
  Settings, senao o material nasce apontando para uma tela que vai sumir.
- Os templates do Guardian se dividem em *Lifecycle guardian (SDLC events)* e
  *Business guardian (Business events)*. Para demonstrar hoje, **Kubernetes
  namespace saturation** sobre o `fiap-bank` e' o que funciona sem nenhuma
  integracao de pipeline; **Four golden signals** e' o que casa com o canary
  do bloco 5.
