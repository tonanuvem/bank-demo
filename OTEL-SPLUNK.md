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

As duas usam o **mesmo** `martian-mongodb` (host:27017), então dá para alternar
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
docker ps --format '{{.Names}}' | grep -qx martian-mongodb || \
  docker run -d --name martian-mongodb --restart unless-stopped \
    -p 27017:27017 -v martian-mongodb-data:/data/db mongo:7
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

Duas rotas, de propósito — cada linguagem pela via que realmente funciona nela.

### 1. Python → OTLP (com correlação de trace)

`OTEL_LOGS_EXPORTER=otlp` faz o `opentelemetry-instrumentation-logging` plugar um
handler na raiz do `logging`. Cada `LogRecord` sai com `trace_id`/`span_id`
nativos, o que acende o **Related Content** do Splunk (do span você pula direto
para os logs daquela requisição).

Validado localmente: de 4 spans gerados por uma chamada, 9 registros de log
saíram carregando o mesmo `trace_id`.

Não use `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true` — está depreciado
e o próprio agente avisa no boot. Sem ele, o handler moderno assume e passa a
respeitar `OTEL_PYTHON_LOG_HANDLER_LEVEL`.

### 2. Node / nginx / UI → log driver `fluentd`

O agente JS só coleta log de `winston`/`pino`/`bunyan`. Estes dois serviços usam
`console.log` e `morgan`, que o agente **não** captura. Então o stdout do
container vai pelo log driver `fluentd` do próprio Docker para o receiver
`fluent_forward`, que o `agent_config.yaml` da Splunk já expõe em `:8006`.

```yaml
logging:
  driver: fluentd
  options:
    fluentd-address: "tcp://127.0.0.1:8006"
    fluentd-async: "true"
    tag: "martianbank.{{.Name}}"
    labels: "service.name,deployment.environment"
```

Três detalhes que só aparecem testando:

- **`127.0.0.1` funciona nas duas variantes de rede.** Quem abre essa conexão é o
  *daemon* do Docker, no host — não o container. Só o caminho OTLP precisa do
  `SPLUNK_LISTEN_INTERFACE=0.0.0.0`.
- **`fluentd-async=true` é obrigatório.** Sem ele, testei: o container **se recusa
  a subir** enquanto o collector estiver fora do ar.
- **`docker logs` continua funcionando** (dual logging do Docker) — também testado.

As labels `service.name` e `deployment.environment` chegam como atributos do log,
que é o que o Log Observer usa para casar com os serviços do APM.

### Pré-requisito: o token do HEC

O pipeline de logs do `agent_config.yaml` exporta via `splunk_hec`, que usa
`${SPLUNK_HEC_TOKEN}`. O seu está **vazio** — sem isso nenhum log chega, pelas
duas rotas. No Splunk Observability o HEC de logs usa o próprio access token da
org (e o seu `SPLUNK_HEC_URL` já aponta para `/v1/log`):

```bash
sudo sed -i "s|^SPLUNK_HEC_TOKEN=.*|SPLUNK_HEC_TOKEN=<seu access token>|" /etc/otel/collector/splunk-otel-collector.conf
sudo systemctl restart splunk-otel-collector
```

O `docker-run-demo-bank.sh` faz isso sozinho.

### Volume de log

As apps chamam `logging.basicConfig(level=logging.DEBUG)`, e nesse nível o driver
do Mongo despeja um `Server heartbeat` a cada 10s **por cliente, mesmo sem
tráfego nenhum**. Numa medição local isso foi de ~80 registros para ~12 ao
silenciar só os loggers ociosos do pymongo — o que os `Dockerfile-otel` já fazem:

```python
for _n in ("pymongo.topology", "pymongo.connection", "pymongo.serverSelection"):
    logging.getLogger(_n).setLevel(logging.WARNING)
```

`pymongo.command` fica ligado de propósito: são as queries reais, e elas saem
correlacionadas com o trace.

Se ainda assim for muito, existe `OTEL_PYTHON_LOG_HANDLER_LEVEL=info` (comentado
no compose) — mas cuidado: as apps logam quase tudo em DEBUG, então `info` faz
sumir justamente as mensagens da aplicação e, com elas, a correlação.


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
