# LAB 3 — Service Mesh e Observabilidade com Dynatrace

**Encontro 3 — Inteligência Operacional e Visibilidade Executiva | 3h**

Terceiro laboratório da trilha. O sistema é o mesmo das aulas 1 e 2 — o FIAP
OTEL Bank, com as mesmas jornadas — agora em Kubernetes, atrás de um service
mesh, observado pelo Dynatrace.

> **Por que o mesmo sistema outra vez.** Na aula 1 o aluno comparou Splunk e
> FIAP Bank; na aula 2, Grafana e FIAP Bank. Se a aula 3 trocasse para o
> BookInfo, a comparação entre as três ferramentas perderia o único
> denominador comum que ela tinha. O BookInfo continua útil como "hello world"
> da malha, mas não como objeto de estudo.

---

## O arco das três aulas

| | O que o aluno fez |
|---|---|
| Aula 1 | **Definiu** o SLO da jornada |
| Aula 2 | **Mediu** o CFR depois do estrago: a v1.3.0 foi para 100% dos usuários |
| Aula 3 | **Impede** o estrago — canary + Guardian + Davis — e, quando não impede, o playbook corrige |

A frase que fecha a trilha, e que vale dizer em voz alta no começo desta aula:
*na aula passada vocês mediram o custo da falha; hoje vocês vão evitá-la.*

---

## Decisão de ambiente: EKS ou kubeadm?

| | kubeadm/EC2 (`shift`) | EKS (`eks`) |
|---|---|---|
| Cluster de pé | ~5 min, determinístico | 15–20 min × 25 alunos |
| Créditos AWS Academy | baixo | alto |
| Fragilidade | scripts próprios | eksctl/IAM/CFN no Learner Lab |
| OneAgent enxerga | host inteiro + control plane como processos | nós gerenciados; control plane invisível |
| Metadata de nuvem | pobre | rica (app Clouds, contexto AWS) |

**Recomendação: kubeadm/EC2 para cada aluno + um único EKS do professor**,
subido antes da aula, **no mesmo tenant**. Os dois clusters aparecem lado a
lado no app Kubernetes e a comparação vira conteúdo — inclusive o alerta de
cobertura de monitoração que o EKS costuma exibir.

> `[PRINT: app Kubernetes → Explorer → Clusters, mostrando os dois clusters e o aviso "2 clusters with monitoring issues"]`

O ponto cego do EKS (`etcd` e `kube-apiserver` não aparecem no Smartscape)
rende cinco minutos sobre observabilidade de serviço gerenciado — assunto caro
para uma instituição financeira.

---

## 0 · Preparação (antes da aula) — 20 min

| Passo | Onde |
|---|---|
| Criar o cluster e instalar o Istio | scripts do ambiente do LAB (`environment/config/{shift,eks}/`) — **outro repositório, não alterado aqui** |
| Subir a aplicação | `bash k8s/run-lab-k8s.sh` |
| Instalar o Dynatrace | `k8s/dynatrace/README.md` |
| **Carga** | sobe junto com o `run-lab-k8s.sh` (`k8s/app/90-carga.yaml`) — **confira que está rodando** |
| Conferir o sidecar | `kubectl -n fiap-bank get pods` — todo pod **2/2**, menos o `mongodb` (1/1 de propósito) |

> **Convivência com o Bookinfo.** O script do ambiente instala o Bookinfo e o
> Gateway dele já ocupa a porta 80 do `istio-ingressgateway` com `hosts: ["*"]`.
> Dois Gateways na mesma porta e host são mesclados pelo Istio num único
> listener, e a ordem das rotas entre eles não é garantida — o `/login` do
> Bookinfo passa a disputar com a tela de login do banco. Por isso o
> `run-lab-k8s.sh` detecta o caso e move o banco para a porta **31400** do
> mesmo gateway: o Bookinfo continua no ar para a demo de Istio, e o banco tem
> listener próprio. A URL impressa no fim do script já leva a porta certa.
> Para forçar: `bash k8s/run-lab-k8s.sh --porta=80`.

> **A carga precisa rodar ANTES.** O Davis constrói linha de base: sem 30–40
> minutos de comportamento saudável ele não tem o que chamar de anomalia, e o
> game day do bloco 4 não produz nenhum card. É por isso que os blocos 1 e 2
> desta aula não tocam no Dynatrace — eles existem também para dar tempo ao
> baseline.

---

## 1 · O cluster se apresenta — 25 min

```bash
kubectl get nodes
kubectl -n fiap-bank get pods
```

Todo pod deve estar **2/2** — aplicação + sidecar Envoy. `1/1` significa que o
rótulo `istio-injection` não estava lá no momento do deploy; o rótulo não é
retroativo.

> `[PRINT: kubectl -n fiap-bank get pods com a coluna READY em 2/2]`

### No Dynatrace

| Tela | Pergunta |
|---|---|
| Kubernetes → Overview | Quanto tempo levou para isso aparecer? Quem configurou este dashboard? |
| Kubernetes → Explorer → Workloads → `transactions` | Por que este pod tem **dois** containers? |
| Smartscape / topologia | Suba do span até o nó EC2. No Grafana, quantas telas isso custaria? |
| Services → `transactions` | Terceiro mapa do mesmo sistema. Qual responde "e daí?" mais rápido? |

> `[PRINT: detalhe do workload transactions mostrando os containers transactions + istio-proxy]`
> `[PRINT: Smartscape — cadeia aplicação → serviço → processo → host]`

**Discussão.** O Splunk e o Grafana mostraram o que vocês instrumentaram. Esta
ferramenta mostra o que existe. O que isso muda no custo de manter um
ambiente observável? E o que isso esconde?

---

## 2 · A malha — 30 min

Kiali e Dynatrace, lado a lado, no mesmo sistema.

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

> `[PRINT: Kiali → Traffic Graph do namespace fiap-bank]`
> `[PRINT: Dynatrace → Distributed Tracing → Service flow da mesma jornada]`

**A pergunta que separa as duas ferramentas:** por que o Kiali **não** mostra a
query no MongoDB, e o Dynatrace mostra?

Resposta: o Kiali enxerga o que passa pelo Envoy — tráfego HTTP entre pods. O
OneAgent instrumenta **dentro** do processo e vê a chamada do driver `pymongo`.
O MongoDB deste lab sobe deliberadamente sem sidecar (`k8s/app/10-mongodb.yaml`)
para que a diferença fique visível.

Vale mostrar também o que o `enableIstio: true` criou:

```bash
kubectl -n dynatrace get serviceentry,virtualservice
```

Sem isso, com mTLS em STRICT, o OneAgent instala, sobe e fica mudo. É um caso
real de *a malha quebrou a observabilidade*.

---

## 3 · SLO e negócio — 25 min

Recriar no Dynatrace **o mesmo SLO** da aula 1 (Splunk) e da aula 2 (Grafana).

> `[PRINT: app Service-Level Objectives com o SLO da jornada de transferência]`

| Tela | Amarra com |
|---|---|
| Service-Level Objectives | o SLO do Splunk (aula 1) e o Error Budget do Grafana (aula 2) |
| Business Flow | o "Business Health" perseguido desde o slide 1 da aula 1 |
| Experience Vitals / Session Replay | a pergunta "sonda sintética ou RUM?" da aula 2 |
| Synthetic monitoring | o `probe_success` do blackbox exporter |

**A pergunta honesta:** três implementações do mesmo contrato de
confiabilidade. Qual delas vocês levariam a uma reunião com o negócio, e por quê?

---

## 4 · Game day — 30 min

Agora a aplicação está intacta e a falha vem da malha.

```bash
bash k8s/caos.sh status
bash k8s/caos.sh delay 7s 50      # lentidão: tudo responde 200
```

Procure, nesta ordem: taxa de erro em **zero**, SLO de latência queimando,
volume de transferências caindo, **log do pod limpo**.

> `[PRINT: SLO de latência queimando enquanto o de disponibilidade segue verde]`

```bash
bash k8s/caos.sh abort 503 20     # erro: 503 direto do Envoy
```

**Cronometre** o tempo até o card do Davis aparecer. Compare com o tempo que o
aluno levou para achar o mesmo sintoma no Grafana da aula passada.

> `[PRINT: card do Davis com causa raiz e entidades afetadas]`

**A pergunta que vale a aula:** o Davis aponta uma causa. Ele acerta? O que ele
diria se soubesse que a falha está no sidecar, e não no processo?

```bash
bash k8s/caos.sh resiliencia on   # circuit breaker
```

A taxa de erro cai em menos de um minuto **sem ninguém ter corrigido nada**.
Por que `maxEjectionPercent` é 50 e não 100?

> **Dois tipos de falha, e o aluno precisa distinguir.** `k8s/app/50-transactions-v2.yaml`
> coloca a falha **dentro** do processo (aparece no log, no stack trace);
> `caos.sh` coloca a falha **na malha** (log limpo). Aplique uma das duas sem
> dizer qual e peça o diagnóstico pela tela.

---

## 5 · Canary, Guardian e playbook — 30 min

```bash
bash k8s/caos.sh canary 20        # 20% do tráfego para a v2 degradada
```

Esta é a **mesma v1.3.0** da aula 2. A diferença: lá ela foi para 100% dos
usuários de uma vez.

> `[PRINT: tile de latência p90 separado por versão, v1 e v2 lado a lado]`

1. O Davis abre problema mesmo com só 20% afetado?
2. O Error Budget queima mais devagar? Em que proporção?
3. 20% de usuários atingidos é preço aceitável para descobrir que a versão
   está ruim? **Qual seria esse número na B3?**

Depois, o **Site Reliability Guardian** avaliando o canary contra o objetivo de
SLO e barrando a promoção dos 80% restantes.

> `[PRINT: Site Reliability Guardian reprovando a validação da v2]`

E o **Workflow** como playbook de N1: problema do Davis dispara, coleta
evidência, publica no canal e (opcional) reverte o VirtualService.

> `[PRINT: Workflow disparado pelo problema, com as etapas executadas]`

É onde o playbook deixa de ser PDF e vira código, com limite explícito de
autonomia — o Bloco 2 da ementa.

---

## 6 · Entrega — 20 min

Cada grupo preenche um **Notebook** de postmortem (estrutura em
`k8s/dynatrace/dql.md`, seção 4): o que aconteceu, quando começou, quantos
clientes, quanto custou, como foi detectado, o que muda estruturalmente.

O entregável é o notebook preenchido, não um print.

```bash
bash k8s/caos.sh limpar     # deixe a carga mais 5 min: o Davis precisa FECHAR o problema
```

Um problema que fecha sozinho é evidência no postmortem — marca a hora exata
em que o impacto cessou.

---

## Encerrar

```bash
kubectl delete namespace fiap-bank
```

E então o `destruir.sh` do ambiente do LAB — o cluster consome créditos mesmo
ocioso. **Rode também no início da aula seguinte**: sempre há aluno com o lab
anterior de pé.

---

## Se o tempo apertar

Corte nesta ordem: bloco 3 (SLO — já foi visto duas vezes), depois a parte de
Workflow do bloco 5. **Não corte** o bloco 4: é o único momento em que o aluno
investiga sem saber a resposta.

---

## Arquivos

```
k8s/
├── README.md                  este roteiro
├── run-lab-k8s.sh             sobe aplicação + malha e aponta a UI para o gateway
├── caos.sh                    injeta falha e divide carga pela malha
├── app/                       manifests do FIAP Bank (00 a 50)
├── istio/                     gateway, subsets, canary, caos, resiliência
└── dynatrace/                 dynakube.yaml, instalação e consultas DQL

A carga (`app/90-carga.yaml`) sobe junto com a aplicação: `curl` em laço,
três réplicas, sem imagem para construir. Os cenários completos de negócio
das aulas 1 e 2 (locust, com `FALHA_PCT`) estão comentados no mesmo arquivo —
exigem publicar a imagem uma vez.
```

**Status: nada disto foi executado contra um cluster.** Os manifests e scripts
passaram por validação de sintaxe apenas. Reserve uma execução a seco antes da
aula — especialmente a `apiVersion` do DynaKube, os nomes de métrica do DQL e o
`FIAP_API_BASE` da UI, que são os três pontos mais prováveis de ajuste.
