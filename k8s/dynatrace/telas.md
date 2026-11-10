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
