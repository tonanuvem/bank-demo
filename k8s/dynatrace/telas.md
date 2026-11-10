# Telas do Dynatrace, uma a uma

Mapa dos `[PRINT: ...]` do `k8s/README.md` para a navegação real, com o que
cada tela exige para ter dado dentro.

> **A regra que organiza tudo:** as telas de AIOps não são *encontradas*, são
> **preparadas**. O card do Davis aparece sozinho, mas detector de anomalia,
> Guardian e Workflow precisam existir **antes** do caos: um detector criado
> depois não tem linha de base, e um Guardian criado depois não tem o "antes"
> da comparação. A seção 4 tem os passos, na ordem de montagem.

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
| p90 subindo com o status em 200 | **Distributed Tracing** → filtro `k8s.namespace.name = fiap-bank` → percentis, durante `caos.sh delay` | caos rodando |
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

Três coisas, todas pela interface, nenhuma passando de cinco minutos de
cliques. O que consome tempo aqui não é montar: é **esperar** a linha de base
(4.4) — e é por isso que esta seção vem antes do bloco 4, não durante.

O SLO saiu desta lista: a decisão e o motivo estão em 8.3. Se você mudar de
ideia, ele precisa existir **antes** do caos, senão não há error budget
gravado para queimar.

A ordem não é arbitrária. Detector e Workflow só valem para frente, então vão
primeiro; o Guardian vai por último, porque a primeira execução dele precisa
de carga saudável já gravada para passar.

### 4.1 Detector de anomalia sobre a taxa de transações

**Por que este detector, e não só o Davis automático:** o `caos.sh delay`
derruba o volume **sem gerar um único erro**. Taxa de erro em zero, log
limpo, 200 em tudo. Quem percebe queda de volume é um detector sobre
*contagem* — e esse você escolhe; o Davis não escolhe por você.

**Monte pela Settings, não pelo app.** O app **Anomaly Detection** mostra o
banner *"moved to Settings. The current will be deprecated by the end of the
year"* (7.5) — material montado em cima dele aponta para uma tela que vai
sumir. Mostre o app na aula se quiser, mas crie o detector aqui:

1. **Settings** → *Anomaly detection* → *Custom events for alerting* →
   *Create custom event for alerting*
2. Métrica: procure `requestCount` no seletor e pegue
   `builtin:service.requestCount.total`
3. Filtre pelo **nome** do serviço `transactions`, não pelo ID da entidade —
   o ID muda a cada recriação do lab, e aí o detector para de avaliar
   qualquer coisa sem avisar
4. Estratégia: **Auto-adaptive baseline**
5. Direção: alertar quando o valor fica **abaixo** da linha de base. É a queda
   que interessa; nos dois sentidos, a própria variação natural da carga alerta
6. Deixe a métrica **dimensionada pelo serviço**: é o que faz o evento se
   anexar à entidade. Sem isso o problema aparece solto — sem causa-raiz, sem
   topologia e sem os *affected entities*, que são o assunto do bloco 4
7. No *event template*, dê um título que o aluno leia sem tradução, ex.
   *"Taxa de transações abaixo do padrão"*
8. Salve e deixe **ligado**

**O aviso que vem do laboratório:** limiar auto-adaptativo aprende de um
período de referência de **dias**. Num lab criado na véspera da aula ele não
tem o que aprender, e pode simplesmente não disparar no game day.

Então monte os dois — e o problema vira material de aula:

- o **auto-adaptativo** você cria para mostrar a tela e o conceito;
- um segundo detector com limiar **estático** é o que de fato dispara. Meça
  a taxa saudável e corte pela metade.

Para medir, com a carga rodando limpa:

```
Notebooks → célula DQL

timeseries req = sum(dt.service.request.count), by: { dt.entity.service }
| fieldsAdd nome = entityName(dt.entity.service)
| filter contains(nome, "transactions")
```

Se o nome da métrica não existir neste tenant, o autocomplete resolve: digite
`dt.service.request` e veja o que ele oferece. O valor também está pronto em
**Services** → `transactions` → *Requests per minute*.

E o par de detectores é a aula inteira em duas linhas: o estático dispara
sempre que o número cruza a linha — é literalmente o alerta do Prometheus da
aula 2 — e o auto-adaptativo só dispara quando o número sai do padrão
aprendido **para aquele horário**. A diferença não é sofisticação, é tempo de
dado: sem história, o auto-adaptativo é pior que o estático.

### 4.2 Site Reliability Guardian com dois objetivos

É ele que reprova a v2 no bloco 5.

1. App **Site Reliability Guardian** → *Create guardian*
2. Template **Four golden signals**
3. Em cada objetivo, troque a entidade pelo serviço `transactions`
4. **Apague os dois objetivos que não interessam** (tráfego e saturação) e
   fique com exatamente dois: **taxa de erro** e **latência**. Não é
   economia — se o guardian reprovar por saturação, você perde a narrativa.
   A reprovação tem que vir pelo motivo que você vai contar em voz alta
5. Ajuste os dois limiares com a conta do canário, abaixo
6. Salve como `transactions-v2`, nome que o aluno reconhece
7. **Rode uma vez com a carga saudável: tem que passar.** É o "antes" da
   comparação; se já reprovar aqui, o limiar está errado, não a aplicação
8. No bloco 5, durante o `caos.sh canary 20`, rode de novo: tem que reprovar

**A conta do canário — sem ela o guardian passa e o bloco 5 não acontece.**

A v2 roda com `FALHA_ARTIFICIAL_PCT=15` e `ATRASO_ARTIFICIAL_MS=1400`. Com
`canary 20`, só 20% do tráfego passa por ela — e v1 e v2 reportam o **mesmo**
nome de serviço (`OTEL_SERVICE_NAME=transactions` nos dois arquivos), então o
guardian avalia a média:

- **taxa de erro:** 20% × 15% = **3%** no serviço. Um limiar de 5% passa
  tranquilo. Use **1%**.
- **latência:** 20% das requisições ficam ~1,4s mais lentas, logo o **p50 não
  se move** e o **p90 sobe ~1,4s** — porque 20% é maior que os 10% do topo da
  distribuição. Escolha **p90**, com limiar entre a linha de base medida e
  ela + 1,4s. Linha de base abaixo de 500ms? 1s resolve.

Esse detalhe é bom demais para passar batido: num `canary 5`, o p90 **não**
pegaria a degradação e o p99 pegaria. O percentil que você escolhe decide se
você enxerga um canário pequeno — e é a mesma razão pela qual o p50 do
dashboard da aula 2 ficava verde.

Se quiser a análise de canário de verdade, v1 contra v2 em vez da média,
divida por `k8s.workload.name`: `transactions` e `transactions-v2` são
Deployments separados, mesmo sendo um serviço só.

**Risco conhecido, de 7.5:** os templates se dividem em *Lifecycle guardian
(SDLC events)* e *Business guardian (Business events)*, e o **Four golden
signals** é do primeiro grupo — pode pedir evento de pipeline que este lab não
emite. Se os objetivos não encontrarem dado, troque para o template
**Kubernetes namespace saturation** sobre o `fiap-bank`, que funciona sem
integração nenhuma. Descubra isso na véspera, não no bloco 5.

### 4.3 Workflow disparado por problema do Davis

É a tela do laço fechado: detecção → decisão → ação, sem humano no meio.

1. App **Workflows** → *Create workflow from template*
2. Template **Auto-Annotate K8s Pods based on Problem Events**
3. No gatilho (*Davis problem trigger*), restrinja ao namespace:
   `matchesValue(k8s.namespace.name, "fiap-bank")`. O autocomplete do campo
   confirma o nome exato do atributo neste tenant; se ele não oferecer
   namespace, deixe o gatilho aberto — neste cluster o único outro app é o
   Bookinfo, então o filtro é higiene, não necessidade
4. Salve e **ligue** (workflow importado de template vem desligado)
5. No game day, depois do card do Davis, mostre o outro lado — o cluster:

```
kubectl -n fiap-bank describe pod <pod> | grep -i annotation
```

O ponto não é a anotação. É o aluno ver uma decisão tomada e executada
enquanto ele ainda estava lendo o problema.

Se o workflow não tiver permissão para escrever no cluster, troque a ação por
um *Run Javascript* que grava num Notebook: a demonstração do laço continua
inteira, e sem depender de `kubectl` nenhum.

### 4.4 A linha de base — a única parte que não se constrói clicando

Se constrói **esperando**. O Davis precisa de 30 a 40 minutos de carga
saudável gravada antes do caos; sem isso ele não tem contra o que comparar e
não abre problema nenhum.

Confira que a carga está limpa **antes** de começar a contar o tempo:

```
kubectl -n fiap-bank logs -l app=stress-carga --since=120s | grep -c HTTP
```

Zero é o número certo: a carga só registra o que não é 2xx. Se vier diferente
de zero, o relógio da linha de base ainda não começou.

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

### 7.1 As CINCO telas da aula, em ordem de acontecimento

| # | Tela | Por que ela, e nao outra |
|---|---|---|
| 1 | **Problems** (Davis) | correlacao e causa raiz sem ninguem escrever regra. Nas aulas 1 e 2 todo alerta foi configurado a mao |
| 2 | **Site Reliability Guardian** | nao e' painel, e' **decisao**: aprova ou reprova uma versao. Nenhuma aula anterior teve portao automatico |
| 3 | **Workflows** | fecha o laco: problema → acao. Observabilidade que *faz*, nao so' mostra |
| 4 | **Distributed Tracing → Service flow** | OneAgent e OpenTelemetry na MESMA jornada -- agente proprietario contra padrao aberto, com evidencia em vez de slide |
| 5 | **Kubernetes → Recommendations** | a unica que funciona sem caos nenhum, e carrega o caso real do OOM da UI deste laboratorio |

Fora da lista de proposito: **Anomaly Detection** e' otimo conceitualmente
(limiar que aprende, contra o limiar fixo do Prometheus), mas o proprio app
avisa que sera' descontinuado no fim do ano -- material montado em cima disso
envelhece em semanas. Se quiser usar, monte pela Settings.

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

---

## 8. O que ja' esta pronto e o que voce precisa construir

A duvida mais pratica, respondida com o que foi verificado neste tenant.

### 8.1 Pronto, sem configurar nada

Tudo abaixo existe pelo simples fato de o agente estar instalado e a carga
rodando. Nao ha o que criar:

| Tela | O que ja' mostra |
|---|---|
| **Kubernetes → Explorer** | cluster, nos, namespaces, workloads |
| **Kubernetes → Recommendations** | sugestao de CPU e memoria por workload (precisa de algumas horas de dado) |
| **Smartscape** | topologia; Service dependency graph com as chamadas entre servicos |
| **Services** | cada processo como servico proprio |
| **Distributed Tracing** | requisicoes, duracao, percentis, filtro por namespace e workload |
| **Logs** | log de todo container, com facetas por workload sem indice nem schema |
| **Experience Vitals** | existe porque o OneAgent injetou RUM na UI (a entidade "My web application") |
| **Problems** | o app esta la'; o CARD so' aparece quando houver anomalia |

### 8.2 Precisa construir — e e' pouco

Tres coisas pela interface, mais uma que nao se constroi clicando.

| O que | Para que serve na aula | Passos |
|---|---|---|
| **Detector de anomalia** sobre a taxa de transacoes | pega a queda de volume do `delay`, que nao gera erro nenhum | secao **4.1** |
| **Site Reliability Guardian**, dois objetivos | reprova a v2 no bloco 5 | secao **4.2** |
| **Workflow** por problema do Davis | fecha o laco: detecao -> decisao -> acao | secao **4.3** |

Os passos ficam na secao 4, junto da ordem em que isso precisa ser montado --
que importa: o Guardian so' passa na primeira execucao se a carga saudavel ja'
estiver gravada.

A quarta coisa e' a que nao tem botao:

**Linha de base.** 30 a 40 minutos de carga saudavel antes do caos. E' espera,
nao configuracao, e e' o unico item desta lista que voce nao consegue fazer as
pressas quando a aula ja' comecou. Detalhe e conferencia em **4.4**.

### 8.3 O que NAO precisa construir, ao contrario do que parece

- **Dashboard**: as telas prontas ja' respondem o que a aula pergunta. Montar
  painel e' repetir a aula 2.
- **SLO**: so' e' necessario se voce quiser mostrar error budget queimando.
  Como isso ja' foi feito no Splunk e no Grafana, fica fora -- mas entao nao
  prometa a tela de SLO queimando no roteiro.
- **Detector de anomalia**: parece dispensavel -- "o Davis detecta sozinho" --
  e nao e'. O Davis automatico olha erro, latencia e saturacao; o `caos.sh
  delay` derruba o VOLUME sem gerar erro algum. Essa queda so' tem quem a veja
  se existir um detector sobre contagem, e esse voce escolhe. Passos em 4.1.

### 8.4 Se o Davis nao abrir problema no game day

Acontece, e nao e' falha de instalacao: pode faltar linha de base, ou a
anomalia pode nao passar do limiar que o Davis aprendeu. Plano B, na ordem:

1. aumente a dose -- `caos.sh abort 503 50` em vez de 20;
2. deixe rodar mais tempo antes de concluir;
3. se ainda assim nao abrir, a propria ausencia e' material de aula: o Davis
   decide o que e' problema a partir do que aprendeu, e isso tem lado bom e
   lado ruim. Compare com o alerta do Prometheus, que dispara sempre que o
   numero cruza a linha, sem perguntar se aquilo e' normal naquele horario.
