# Martian Bank -> Splunk Observability Cloud (APM + RUM)

Instrumentação **sem alterar o código da aplicação**: tudo vive em
`Dockerfile-otel` por serviço + dois `docker-compose` alternativos.

## Arquivos criados

| Arquivo | Papel |
|---|---|
| `accounts/Dockerfile-otel`, `loan/Dockerfile-otel`, `transactions/Dockerfile-otel`, `dashboard/Dockerfile-otel` | Python + `splunk-opentelemetry` + `opentelemetry-instrument` |
| `customer-auth/Dockerfile-otel`, `atm-locator/Dockerfile-otel` | Node **20** (ESM) + `@splunk/otel` + loader hook |
| `ui/Dockerfile-otel`, `ui/otel-rum-entrypoint.sh` | Splunk RUM injetado no `index.html` em runtime |
| `nginx/default-host.conf` | upstreams em `127.0.0.1` (necessário em host mode) |
| `docker-compose-network-mode-host.yml` | **Variante A** — `network_mode: host` |
| `docker-compose-network-docker-internal.yml` | **Variante B** — bridge + `host.docker.internal` |
| `.env.otel.example` | variáveis (realm, env, token de RUM) |
| `../splunk/docker-run-demo-bank.sh` | instalador ponta a ponta (clona, configura o collector, sobe tudo, testa) |

## Qual variante usar

| | A — `network_mode: host` | B — bridge + `host.docker.internal` |
|---|---|---|
| Mexe no collector? | **Não** | **Sim** (`SPLUNK_LISTEN_INTERFACE=0.0.0.0`) |
| Endpoint OTLP | `http://localhost:4317` | `http://host.docker.internal:4317` |
| Isolamento de rede | nenhum | real (DNS interno, `ports:`) |
| Conflito de porta | com a EC2 inteira | só nas portas publicadas |
| Recomendação | **comece por aqui** | depois, para mostrar o cenário "prod" |

As duas usam o **mesmo** `fiap-mongodb` (host:27017), então dá para alternar
sem perder dados.

## Passo a passo

```bash
cp .env.otel.example .env
vi .env                      # SPLUNK_REALM, DEPLOYMENT_ENV, SPLUNK_RUM_TOKEN
```

### Antes de subir (variante A)

O host mode disputa porta com a EC2. Pare o que o `run-demo-bank.sh` deixou
rodando nativo:

```bash
sudo lsof -i:3000 -i:5000 -i:8000 -i:8001 -i:50051 -i:50052 -i:50053
```

MongoDB precisa existir:

```bash
docker ps --format '{{.Names}}' | grep -qx fiap-mongodb || \
  docker run -d --name fiap-mongodb --restart unless-stopped \
    -p 27017:27017 -v fiap-mongodb-data:/data/db mongo:7
```

Subir:

```bash
docker compose -f docker-compose-network-mode-host.yml up -d --build
```

### Antes de subir (variante B)

O collector hoje só escuta em `127.0.0.1`. Containers em bridge chegam pelo
gateway (`172.17.0.1`), não pelo loopback — sem esta mudança **tudo dá
connection refused**:

```bash
echo 'SPLUNK_LISTEN_INTERFACE=0.0.0.0' | sudo tee -a /etc/otel/collector/splunk-otel-collector.conf
sudo systemctl restart splunk-otel-collector
sudo ss -lntp | grep -E '4317|4318'   # esperado: 0.0.0.0:4317
```

Se a variável não pegar na sua versão, edite os `endpoint:` do receiver `otlp`
em `/etc/otel/collector/agent_config.yaml`.

> **Segurança:** `0.0.0.0` também abre 4317/4318 na interface pública da EC2.
> Confirme que o Security Group não libera essas portas.

Subir:

```bash
docker compose -f docker-compose-network-docker-internal.yml up -d --build
```

## Logs

> **Correção importante.** A orientação anterior aqui dizia para preencher
> `SPLUNK_HEC_TOKEN` e os logs chegariam ao Log Observer. **Isso não funciona
> mais.** O Splunk Observability Cloud não aceita ingestão direta de logs: o
> Log Observer nativo foi descontinuado em favor do **Log Observer Connect**,
> que lê logs de um Splunk Cloud/Enterprise em vez de recebê-los.
>
> Verificável em um comando, sem token nenhum:
>
> ```
> POST https://ingest.us1.observability.splunkcloud.com/v1/log   -> 404
> POST https://ingest.us1.signalfx.com/v1/log                    -> 404
> POST https://ingest.us1.observability.splunkcloud.com/v2/datapoint -> 401
> ```
>
> O `401` no endpoint de métricas/traces prova que o host está vivo e só
> recusa por falta de credencial. O `404` no `/v1/log` é o caminho não
> existindo. Com o exporter ligado contra ele, o collector entra em **retry
> infinito**, enchendo o journal de `Exporting failed`.

Por isso o default passou a ser `OTEL_LOGS_EXPORTER=none`, e o log driver
`fluentd` está comentado nos dois compose. **Os traces (APM) não são afetados**
— usam outro pipeline, com outro exporter.

### Como os logs foram implementados (e como religar)

A implementação continua no repo, pronta, em duas rotas:

| | Como | Por quê |
|---|---|---|
| Python (4 serviços) | OTLP → `otlp:4317` | correlação nativa: `trace_id`/`span_id` dentro do LogRecord |
| Node, nginx, UI | log driver `fluentd` → `fluent_forward:8006` | o agente JS só coleta winston/pino/bunyan; esses apps usam `console.log` e `morgan` |

Para religar, é preciso um destino que aceite HEC — um Splunk Cloud ou
Enterprise, com o Log Observer Connect ligado por cima:

1. Aponte o collector para ele:
   `SPLUNK_HEC_URL=https://<host>:8088/services/collector` e
   `SPLUNK_HEC_TOKEN=<token do HEC>` em
   `/etc/otel/collector/splunk-otel-collector.conf`.
2. `OTEL_LOGS_EXPORTER=otlp` no `.env`.
3. Descomente `logging: *fluentd-logging` nos serviços dos compose.

O `docker-run-demo-bank.sh` testa o endpoint sozinho antes de decidir, e
respeita `SPLUNK_HEC_URL`/`SPLUNK_HEC_TOKEN` se você passar no ambiente.

Três detalhes do log driver `fluentd` que só apareceram testando, e que
continuam valendo quando for religado:

- **`127.0.0.1` funciona nas duas variantes de rede.** Quem abre a conexão é o
  *daemon* do Docker, no host — não o container. Só o caminho OTLP precisa do
  `SPLUNK_LISTEN_INTERFACE=0.0.0.0`.
- **`fluentd-async=true` é obrigatório.** Sem ele o container **se recusa a
  subir** enquanto o collector estiver fora do ar.
- **`docker logs` continua funcionando** (dual logging do Docker).

### Volume de log

As apps chamam `logging.basicConfig(level=logging.DEBUG)`, e nesse nível o
driver do Mongo despeja um `Server heartbeat` a cada 10s **por cliente, mesmo
sem tráfego**. Numa medição local isso foi de ~80 registros para ~12 ao
silenciar só os loggers ociosos do pymongo — o que os `Dockerfile-otel` já
fazem, mantendo `pymongo.command` (as queries reais, correlacionadas).

### Enquanto isso, os logs locais

```bash
docker compose -f docker-compose-network-mode-host.yml logs -f dashboard
```

## Verificação

```bash
# 1) o app instrumentou? (procure "Instrumenting" / ausência de tracebacks)
docker compose -f docker-compose-network-mode-host.yml logs dashboard | head -40

# 2) o collector está recebendo? (procure TracesExporter / spans)
sudo journalctl -u splunk-otel-collector -f | grep -i -E 'traces|otlp|refused'

# 3) gere tráfego e olhe o APM
curl -s localhost:5000/ ; echo
```

No Splunk: **APM > Services**, filtrando por `Environment = lab-fiap`. Devem
aparecer `dashboard`, `accounts`, `transactions`, `loan`, `customer-auth`,
`atm-locator`. O `dashboard` é o nó central — ele chama os outros via
`requests`, e é essa instrumentação que gera o trace distribuído.

### Os 404 na raiz dos serviços Node são esperados

`customer-auth` e `atm-locator` não têm rota em `/` — as rotas vivem em
`/api/users` e `/api/atm`. Um `curl http://localhost:8000` devolve **404 do
próprio Express**, o que significa que o serviço está no ar. Os dois expõem
**Swagger UI em `/docs`** (e o JSON em `/docs.json`), que é o que o script usa
como teste de saúde, já que devolve 200 e exercita a aplicação de verdade.

Os serviços Python (`dashboard`, `accounts`, `transactions`, `loan`) não têm
Swagger. O `dashboard` responde 200 em `/` com `"Dashboard is running..."`.

Um detalhe que engana: `POST /api/atm` sem a barra final bate no
`@app.route("/api/atm/")` do dashboard e recebe um 308 de redirecionamento,
que o `curl` não segue em POST por padrão. Use `/api/atm/`.


## Pré-requisito da UI (independe de OTel)

`ui/src/slices/apiUrls.js` no repo original aponta para `localhost:8000` etc. —
do ponto de vista do **navegador**, isso é a máquina do usuário, não a EC2.
O `run-demo-bank.sh` já corrige isso para `window.location.hostname`. Confirme:

```bash
grep -n "window.location.hostname" ui/src/slices/apiUrls.js
```

Se não aparecer, aplique o mesmo patch do `run-demo-bank.sh` — senão a UI não
fala com o backend e o RUM não terá o que correlacionar.

## RUM (frontend)

O agente vai no navegador e manda span **direto** para
`https://rum-ingest.<realm>.observability.splunkcloud.com/v1/rum`. Não passa
pelo collector, não usa 4317/4318.

- O token é um **RUM access token** (escopo RUM), diferente do token de ingest.
  Ele fica público no HTML — é assim por design.
- `propagateTraceHeaderCorsUrls` está restrito às portas 5000/8000/8001 do
  próprio host. Não use `/.*/`: o `traceparent` iria para CDN e Google Fonts e
  quebraria essas chamadas por CORS.
- Para o link **RUM -> APM** fechar, o navegador precisa ler o header
  `Server-Timing` das respostas. O `dashboard/Dockerfile-otel` já ajusta o
  `CORS(app)` para expor esse header. No `customer-auth`/`atm-locator` o
  middleware `cors({origin:true})` reflete os headers da requisição, mas
  `Server-Timing` ainda precisaria de `exposedHeaders` se você quiser a
  correlação também nesses dois.

## Isto é OpenTelemetry ou é Splunk?

Pergunta que sempre aparece em sala. A resposta curta: **a instrumentação das
aplicações é OpenTelemetry puro**. O que é da Splunk está em duas bordas —
um pacote fino de "distro" e o destino configurado no collector.

### O que é upstream (funciona com qualquer backend)

- O comando `opentelemetry-instrument` e o `opentelemetry-bootstrap`.
- Todas as bibliotecas de instrumentação: `opentelemetry-instrumentation-flask`,
  `-requests`, `-grpc`, `-pymongo`, `-logging`. São os pacotes do projeto
  OpenTelemetry, sem fork.
- Todas as variáveis `OTEL_*` usadas nos compose: `OTEL_SERVICE_NAME`,
  `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_EXPORTER_OTLP_ENDPOINT`,
  `OTEL_LOGS_EXPORTER`, `OTEL_METRICS_EXPORTER`, `OTEL_PYTHON_LOG_*`.
- O protocolo OTLP (4317 gRPC / 4318 HTTP) e o receiver `fluent_forward`.

### O que é da Splunk

O pacote `splunk-opentelemetry` (11 módulos Python) se registra como um
*distro* pelo entry point padrão do próprio OpenTelemetry:

```
opentelemetry_distro -> splunk_distro = splunk_otel.distro:SplunkDistro
```

Ou seja: é um plugin que o `opentelemetry-instrument` carrega, não um
substituto. Ele importa tudo de `opentelemetry.*` e só ajusta defaults —
propagadores (W3C + B3), limites de span sem truncagem, o header
`Server-Timing` que fecha a correlação RUM→APM, e as variáveis `SPLUNK_*`
(access token, realm, profiler).

O resto do acoplamento vive **fora das aplicações**: os exporters
`signalfx` e `splunk_hec` no `agent_config.yaml` do collector, e o agente
de RUM do browser.

### Prova prática

Toda a validação deste repo foi feita contra um
**`otel/opentelemetry-collector-contrib` puro** com exporter `debug` — nenhum
componente da Splunk envolvido. Traces, logs correlacionados e o caminho do
log driver `fluentd` funcionaram igual.

### Para apontar para outro backend

Troque o **exporter do collector** (`otlp` para Jaeger/Tempo/Grafana,
`datadog`, `elasticsearch`, o que for) e, se quiser remover o último
resquício de fornecedor, tire o `pip install splunk-opentelemetry` dos
`Dockerfile-otel`. Os serviços, os `ENTRYPOINT` e as variáveis `OTEL_*`
ficam exatamente como estão. O que muda é o destino, não a instrumentação.

Sem a distro você perde: o `Server-Timing` (correlação RUM→APM), o
AlwaysOn Profiling e o envio direto ao Splunk sem collector.

## Sobre a plataforma das imagens

Os `Dockerfile` originais fixavam `FROM --platform=linux/amd64`, o que faz o
BuildKit avisar `FromPlatformFlagConstDisallowed` em todo build. O pin foi
removido de todos os Dockerfiles: na EC2 (x86_64) o resultado é idêntico, e em
máquina ARM (Apple Silicon) a imagem passa a ser construída nativamente, em vez
de emulada. Para forçar uma arquitetura sem reintroduzir o aviso:

```bash
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker compose -f <arquivo> build
```


## Ressalvas conhecidas

1. **Os `Dockerfile-otel` não regeneram os `*_pb2.py`** — e isso não é preguiça,
   é um bug real que eu bati de frente ao testar. O `splunk-opentelemetry` traz
   o `opentelemetry-opamp-client`, que exige `protobuf<7.0`, então o runtime cai
   para 6.33.x. Mas o `grpcio-tools` atual (1.84) gera código com gencode 7.35.1,
   e o protobuf recusa rodar gencode mais novo que o runtime:

   ```
   VersionError: gencode 7.35.1 runtime 6.33.6
   ```

   O container **nem sobe**. Os `*_pb2.py` versionados no repo usam gencode
   antigo e funcionam com qualquer runtime moderno, então os `Dockerfile-otel`
   simplesmente não os sobrescrevem. Se um dia você mexer nos `.proto`, fixe
   `grpcio-tools==1.81.1` (protoc que casa com protobuf 6.x) e descomente as
   linhas do `protoc` — já estão lá, comentadas.

2. **Node exporta na porta 4318, não 4317.** Essa é a pegadinha que mais custou
   a aparecer no teste. O `@splunk/otel` 4.x usa **OTLP/HTTP** por padrão, enquanto
   o agente Python usa **gRPC**. Apontando o Node para 4317, ele instrumenta tudo
   corretamente e depois falha no envio com:

   ```
   Export failed with non-retryable error: Parse Error: Expected HTTP/, RTSP/ or ICE/
   ```

   Ou seja: erro só no log do container, e **zero spans no Splunk**. Por isso os
   dois serviços Node sobrescrevem o endpoint para `:4318` nos compose. O collector
   da Splunk expõe as duas portas, então não é preciso mudar nada nele.

3. **Node ESM funciona, mas via caminho experimental.** Os dois serviços são
   `"type":"module"`. Em ESM, `import` não passa pelo `Module._load`, então
   `-r @splunk/otel/instrument` sozinho não instrumenta nada — daí o
   `--experimental-loader=@opentelemetry/instrumentation/hook.mjs`. Validei o
   `customer-auth` rodando: saíram spans de `express` (`POST /api/users/auth`),
   dos middlewares e do `mongoose` (`findOne users`). O Node avisa que
   `--experimental-loader` pode ser removido no futuro. Se quebrar numa
   atualização, volte só esse serviço para o `Dockerfile` original — o Python
   não depende disso.
   Também troquei `node:14` (EOL) por `node:20`: o `@splunk/otel` 4.x exige Node ^18.19 ou >= 20.6.

4. **Flask com `debug=True` sobrevive ao reloader.** Testei: o log mostra
   `* Restarting with stat` e o processo filho continua instrumentado (herda o
   `PYTHONPATH`). Os spans saem normalmente. O `sed` que desliga o reloader
   continua nos Dockerfiles, comentado, como plano B.

5. **Profiling desligado.** AlwaysOn Profiling depende do pipeline HEC e de
   entitlement de APM. Ligue em `SPLUNK_PROFILER_ENABLED=true` no `.env` depois
   que os logs estiverem chegando.

6. **Métricas custom desligadas** (`OTEL_METRICS_EXPORTER=none`) para não
   consumir cota de MTS da org de trial. O APM não precisa delas: as métricas
   de serviço são derivadas dos spans.

7. **`SERVICE_PROTOCOL=http`.** Nessa configuração `dashboard -> accounts/loan/transactions`
   é HTTP (portas 50051/50052/50053), e a propagação de contexto vem da
   instrumentação de `requests`. Validei localmente: uma chamada em
   `dashboard:5000/account/allaccounts` gerou **um único trace com 4 spans**
   atravessando os dois containers (`POST /account/allaccounts` → `POST` client
   → `POST /get-all-accounts` → `bank.find` do pymongo).

## O que foi validado localmente

Com Docker Desktop, um collector de teste (`otlp` + `fluent_forward` → exporter
`debug`) e MongoDB real:

| Item | Resultado |
|---|---|
| Build das imagens Python | ✅ |
| App sobe e responde | ✅ HTTP 200 |
| Spans de Flask e pymongo | ✅ |
| Trace distribuído entre containers | ✅ 1 trace, 4 spans |
| Logs Python via OTLP | ✅ |
| Correlação log ↔ trace | ✅ 9 registros com o `trace_id` do span |
| Filtro de ruído do pymongo | ✅ ~80 → ~12 registros |
| Log driver `fluentd` → `:8006` | ✅ com `service.name` e `deployment.environment` |
| `docker logs` com driver fluentd | ✅ (dual logging) |
| `fluentd-async=false` | ❌ container não sobe sem collector (por isso `true`) |
| Build da imagem Node (customer-auth) | ✅ |
| Instrumentação ESM do Node | ✅ spans de express + mongoose |
| Node contra a porta 4317 | ❌ falha no export (por isso 4318) |
| Build da imagem da UI | ✅ |
| UI servindo o HTML com o agente RUM injetado | ✅ via `curl localhost:3000` |
| Sintaxe dos dois compose | ✅ `docker compose config` |

Não foi testado localmente: o envio real para o Splunk Cloud (precisa dos seus
tokens), o agente RUM executando no navegador de verdade, e o `atm-locator` em
execução (mesma receita já validada no `customer-auth`).

## Referências

- [Requisitos do agente Python](https://help.splunk.com/en/splunk-observability-cloud/manage-data/instrument-back-end-services/instrument-back-end-applications-to-send-spans-to-splunk-apm/instrument-a-python-application/requirements)
- [splunk-otel-python (GitHub)](https://github.com/signalfx/splunk-otel-python)
- [splunk-otel-js (GitHub)](https://github.com/signalfx/splunk-otel-js)
- [Configurar o agente RUM de browser](https://help.splunk.com/en/splunk-observability-cloud/manage-data/instrument-front-end-applications/instrument-mobile-and-web-applications-for-splunk-real-user-monitoring-rum/instrument-browser-applications-for-splunk-rum/configure-the-splunk-rum-browser-agent)
