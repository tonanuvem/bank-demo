#!/bin/sh
# ---------------------------------------------------------------------------
# Injeta o Splunk RUM browser agent no index.html EM TEMPO DE EXECUCAO.
#
# Por que em runtime e nao no build? Porque assim a mesma imagem serve para
# qualquer realm/token/ambiente: basta trocar as variaveis no docker-compose.
# O vite dev server le o index.html do disco a cada request, entao a injecao
# antes do `npm run ui` e' suficiente.
#
# Variaveis esperadas:
#   SPLUNK_RUM_TOKEN      (obrigatoria - SEM ela nada e' injetado)
#   SPLUNK_RUM_REALM      ex: us1
#   SPLUNK_RUM_APP_NAME   ex: fiap-bank-ui
#   DEPLOYMENT_ENV        ex: lab-fiap  (precisa bater com o do backend!)
#   APP_VERSION           ex: 1.0.0
# ---------------------------------------------------------------------------
set -e

# A imagem agora serve o build de producao (dist/). O index.html que o
# navegador recebe e' o de la', e e' nele que tudo abaixo injeta. O caminho
# antigo fica como alternativa para quem ainda rode o vite em modo dev.
if [ -f /bankapp/dist/index.html ]; then
  INDEX="/bankapp/dist/index.html"
else
  INDEX="/bankapp/index.html"
fi
FARO_COLLECTOR_URL="${FARO_COLLECTOR_URL:-}"

if [ -z "$SPLUNK_RUM_TOKEN" ]; then
  echo "[splunk-rum] SPLUNK_RUM_TOKEN vazio - RUM desabilitado."
elif grep -q "SPLUNK-RUM-START" "$INDEX" 2>/dev/null; then
  echo "[splunk-rum] snippet ja presente em $INDEX - nada a fazer."
else
  echo "[splunk-rum] injetando agente RUM em $INDEX (realm=${SPLUNK_RUM_REALM:-us1})"

  cat > /tmp/rum-snippet.html <<SNIPPET
    <!-- SPLUNK-RUM-START (injetado por otel-rum-entrypoint.sh) -->
    <script src="https://cdn.observability.splunkcloud.com/o11y-gdi-rum/latest/splunk-otel-web.js" crossorigin="anonymous"></script>
    <script>
      SplunkRum.init({
        realm: '${SPLUNK_RUM_REALM:-us1}',
        rumAccessToken: '${SPLUNK_RUM_TOKEN}',
        applicationName: '${SPLUNK_RUM_APP_NAME:-fiap-bank-ui}',
        deploymentEnvironment: '${DEPLOYMENT_ENV:-lab-fiap}',
        version: '${APP_VERSION:-1.0.0}',
        // Correlacao RUM -> APM: propaga o header traceparent APENAS para as
        // APIs do proprio host (dashboard:5000, customer-auth:8000,
        // atm-locator:8001). Nao use /.*/  aqui: isso mandaria traceparent
        // para CDNs e fontes externas e quebraria as chamadas por CORS.
        tracing: {
          propagateTraceHeaderCorsUrls: [
            new RegExp('^https?://' + window.location.hostname + ':(5000|8000|8001)/'),
            new RegExp('^https?://' + window.location.hostname + ':8080/api/')
          ]
        }
      });
    </script>
    <!-- SPLUNK-RUM-END -->
SNIPPET

  # Escreve NO LUGAR (cat >) em vez de mv: se o index.html estiver bind-montado
  # do host, o mv falha com "Resource busy" e derruba o container.
  awk '/<\/head>/ && !done { while ((getline line < "/tmp/rum-snippet.html") > 0) print line; done=1 } { print }' \
      "$INDEX" > /tmp/index.html.new && cat /tmp/index.html.new > "$INDEX"

  echo "[splunk-rum] OK."
fi

# ---------------------------------------------------------------------------
# GRAFANA FARO -- RUM do stack aberto.
#
# Mesmo mecanismo do bloco acima, outro fornecedor: os dois sao 100%
# client-side e o navegador envia direto para o coletor. Nenhum dos dois passa
# pelo backend da aplicacao.
#
# Ligado por FARO_COLLECTOR_URL. SEM ela, nada e' injetado -- e' o que mantem
# esta imagem servindo tambem quem nao usa Faro.
#
# ATENCAO ao endereco: quem faz a requisicao e' o NAVEGADOR do aluno, nao o
# container. Entao a URL precisa ser alcancavel de fora (o IP publico da
# maquina, ou localhost quando o navegador roda na mesma maquina) -- nunca o
# nome DNS interno do compose.
# ---------------------------------------------------------------------------

FARO_VERSAO="${FARO_VERSAO:-2.12.0}"

if [ -z "$FARO_COLLECTOR_URL" ]; then
  echo "[faro] FARO_COLLECTOR_URL vazio - RUM do Grafana desabilitado."
elif grep -q "FARO-RUM-START" "$INDEX" 2>/dev/null; then
  echo "[faro] snippet ja presente em $INDEX - nada a fazer."
else
  echo "[faro] injetando Faro ${FARO_VERSAO} em $INDEX (coletor: ${FARO_COLLECTOR_URL})"

  cat > /tmp/faro-snippet.html <<SNIPPET
    <!-- FARO-RUM-START (injetado por otel-rum-entrypoint.sh) -->
    <script src="https://cdn.jsdelivr.net/npm/@grafana/faro-web-sdk@${FARO_VERSAO}/dist/bundle/faro-web-sdk.iife.js" crossorigin="anonymous"></script>
    <script src="https://cdn.jsdelivr.net/npm/@grafana/faro-web-tracing@${FARO_VERSAO}/dist/bundle/faro-web-tracing.iife.js" crossorigin="anonymous"></script>
    <script>
      GrafanaFaroWebSdk.initializeFaro({
        // "auto" resolve pelo hostname que o NAVEGADOR usou -- mesma razao do
        // apiUrls.js. Assim a mesma imagem serve localhost, IP publico e
        // qualquer DNS, e o RUM nao depende de o instalador ter adivinhado
        // certo o endereco externo da maquina.
        url: ('${FARO_COLLECTOR_URL}' === 'auto')
             ? window.location.protocol + '//' + window.location.hostname + ':8027/collect'
             : '${FARO_COLLECTOR_URL}',
        app: {
          name: '${FARO_APP_NAME:-fiap-bank-ui}',
          version: '${APP_VERSION:-1.0.0}',
          environment: '${DEPLOYMENT_ENV:-lab-fiap}'
        },
        instrumentations: [
          ...GrafanaFaroWebSdk.getWebInstrumentations(),
          new GrafanaFaroWebTracing.TracingInstrumentation()
        ]
      });
    </script>
    <!-- FARO-RUM-END -->
SNIPPET

  awk '/<\/head>/ && !done { while ((getline line < "/tmp/faro-snippet.html") > 0) print line; done=1 } { print }' \
      "$INDEX" > /tmp/index.html.faro && cat /tmp/index.html.faro > "$INDEX"

  echo "[faro] OK."
fi



# ---------------------------------------------------------------------------
# DYNATRACE RUM -- terceiro fornecedor, mesmo mecanismo.
#
# POR QUE MANUAL, se o OneAgent injeta RUM sozinho:
# o OneAgent injeta reescrevendo a resposta HTML do servidor web. Aqui o
# servidor e' o vite em modo DEV, e ele nao e' instrumentado. Medido neste
# laboratorio, com o OneAgent comprovadamente carregado no processo
# (liboneagentproc aparece 5x em /proc/1/maps do container da ui):
#
#   $ curl -D - -o /dev/null http://IP:30400/
#   HTTP/1.1 200 OK
#   content-type: text/html
#   transfer-encoding: chunked
#   ...sem Server-Timing, sem x-dynatrace
#
# Sem Server-Timing na resposta nao ha injecao automatica, e sem agente no
# navegador nao existe o salto navegador -> backend no Service flow: a
# aplicacao web aparece solta no Smartscape, por mais que se navegue na tela.
#
#   DT_RUM_SRC  URL do agente, copiada do tenant em
#               <aplicacao web> > Settings > Instrumentation > JavaScript tag
#               > Manual insertion. Tem este formato:
#               https://<tenant>.live.dynatrace.com/jstag/<hash>/<appId>_complete.js
#
# Nao e' preciso configurar propagacao: o RUM da Dynatrace ja' manda
# traceparent em XHR e fetch de MESMA ORIGEM por padrao, e no LAB 3 tudo
# entra por :30400 (ver FIAP_API_BASE abaixo). Isso vale tambem para os
# servicos Python instrumentados por OpenTelemetry.
# ---------------------------------------------------------------------------

DT_RUM_SRC="${DT_RUM_SRC:-}"

if [ -z "$DT_RUM_SRC" ]; then
  echo "[dynatrace-rum] DT_RUM_SRC vazio - RUM da Dynatrace desabilitado."
elif grep -q "DT-RUM-START" "$INDEX" 2>/dev/null; then
  echo "[dynatrace-rum] snippet ja presente em $INDEX - nada a fazer."
else
  echo "[dynatrace-rum] injetando agente em $INDEX"

  cat > /tmp/dt-snippet.html <<SNIPPET
    <!-- DT-RUM-START (injetado por otel-rum-entrypoint.sh) -->
    <script src="${DT_RUM_SRC}" crossorigin="anonymous"></script>
    <!-- DT-RUM-END -->
SNIPPET

  awk '/<\/head>/ && !done { while ((getline line < "/tmp/dt-snippet.html") > 0) print line; done=1 } { print }' \
      "$INDEX" > /tmp/index.html.dt && cat /tmp/index.html.dt > "$INDEX"

  echo "[dynatrace-rum] OK."
fi

# ---------------------------------------------------------------------------
# PORTA DO DASHBOARD -- injetada em tempo de execucao, como o agente de RUM.
# O apiUrls.js le window.__FIAP_API__.dashboard e cai para 5000 se nao houver.
# ---------------------------------------------------------------------------
PORTA_DASHBOARD="${PORTA_DASHBOARD:-5000}"

# FIAP_API_BASE -- origem unica, usada quando a aplicacao roda atras de um
# proxy ou de um gateway (Kubernetes + Istio, no LAB 3).
#
# Vazio (padrao): comportamento das aulas 1 e 2 -- o navegador chama o mesmo
# host em tres portas (dashboard, 8000 e 8001), que e' o que o docker-compose
# publica.
#
# Preenchido (ex.: http://54.1.2.3:31380): TODAS as chamadas vao para essa
# origem e o CAMINHO distingue o destino. E' o unico modo que funciona em
# Kubernetes, onde NodePort so' abre portas acima de 30000 e `:8000` nao
# existe do lado de fora.
FIAP_API_BASE="${FIAP_API_BASE:-}"

if ! grep -q "FIAP-API-START" "$INDEX" 2>/dev/null; then
  if [ -n "$FIAP_API_BASE" ]; then
    echo "[api] origem unica: ${FIAP_API_BASE}"
  else
    echo "[api] dashboard na porta ${PORTA_DASHBOARD}"
  fi
  cat > /tmp/api-snippet.html <<SNIPPET
    <!-- FIAP-API-START (injetado por otel-rum-entrypoint.sh) -->
    <script>window.__FIAP_API__ = { dashboard: ${PORTA_DASHBOARD}, base: "${FIAP_API_BASE}" };</script>
    <!-- FIAP-API-END -->
SNIPPET
  awk '/<\/head>/ && !done { while ((getline line < "/tmp/api-snippet.html") > 0) print line; done=1 } { print }' \
      "$INDEX" > /tmp/index.html.api && cat /tmp/index.html.api > "$INDEX"
fi

exec "$@"
