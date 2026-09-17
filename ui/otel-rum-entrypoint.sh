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

INDEX="/bankapp/index.html"

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

exec "$@"
