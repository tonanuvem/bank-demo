# =============================================================================
# TRECHO PARA ANEXAR AO FINAL DO dynatrace-config.sh
# =============================================================================
# O script original cuida do DynaKube PRINCIPAL: tira o mount do AppArmor e
# ajusta recursos e imagem do ActiveGate. Ele exclui o "-agents" de proposito
# (`grep -v -- '-agents$'`), e e' exatamente ali que ficam o code module, o
# log monitoring e o coletor OTLP.
#
# Este trecho cobre o que sobrou, em tres passos, nenhum deles gerando token:
#
#   1. reinjeta nos workloads da aplicacao -- a injecao acontece no webhook,
#      na CRIACAO do pod, e nao e' retroativa: quem ja' estava rodando quando
#      o DynaKube ficou pronto nunca recebe o code module;
#   2. (opcional) migra applicationMonitoring -> cloudNativeFullStack, que e'
#      o que acrescenta a camada de host e processo no Smartscape;
#   3. VERIFICA se o dado esta chegando, lendo o log do coletor.
#
# O passo 3 e' o que distingue "instalou" de "esta chegando". Medido neste
# laboratorio: pods Ready, zero erro na aplicacao, e 729 spans descartados
# pelo coletor por falta de escopo no token. Quem sabia do descarte era so' o
# coletor.
#
# Compativel com `set -Eeuo pipefail`: todo comando que pode falhar sem ser
# erro esta guardado com `|| true`.
# =============================================================================

NS_APP="${NS_APP:-fiap-bank}"     # namespace da aplicacao a reinjetar
FULLSTACK="${FULLSTACK:-false}"   # true migra para cloudNativeFullStack

echo "=========================================="
echo " Pos-instalacao: agentes, injecao e entrega"
echo "=========================================="

# O DynaKube de agentes e' o que tem a chave oneAgent -- descoberto, nao
# adivinhado pelo nome, porque o assistente muda o sufixo entre versoes.
DK_AGENTES=$(kubectl -n "$NAMESPACE" get dynakube \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.oneAgent}{"\n"}{end}' 2>/dev/null \
  | awk 'NF>1 {print $1; exit}' || true)

if [[ -z "$DK_AGENTES" ]]; then
    echo "AVISO: nenhum DynaKube com oneAgent. A aplicacao nao tera' trace."
else
    echo "DynaKube de agentes: $DK_AGENTES"

    # ---- 2. full-stack, se pedido -------------------------------------------
    if [[ "$FULLSTACK" == "true" ]]; then
        MODO=$(kubectl -n "$NAMESPACE" get dynakube "$DK_AGENTES" \
               -o jsonpath='{.spec.oneAgent}' 2>/dev/null || true)
        if [[ "$MODO" == *applicationMonitoring* ]]; then
            echo "Migrando para cloudNativeFullStack..."
            kubectl -n "$NAMESPACE" patch dynakube "$DK_AGENTES" --type=json -p \
              '[{"op":"remove","path":"/spec/oneAgent/applicationMonitoring"},
                {"op":"add","path":"/spec/oneAgent/cloudNativeFullStack","value":{}}]' || true
        else
            echo "oneAgent ja' nao esta em applicationMonitoring -- nada a fazer."
        fi
    fi
fi

# ---- 1. reinjecao nos workloads da aplicacao --------------------------------
if kubectl get ns "$NS_APP" >/dev/null 2>&1; then
    TOTAL=$(kubectl -n "$NS_APP" get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
    COM=$(kubectl -n "$NS_APP" get pods \
          -o jsonpath='{range .items[*]}{.spec.initContainers[*].name}{"\n"}{end}' 2>/dev/null \
          | grep -c dynatrace || true)
    echo "Injecao em $NS_APP: $COM de $TOTAL pod(s) com o code module"
    if [[ "$COM" -lt "$TOTAL" ]]; then
        echo "Reiniciando os Deployments de $NS_APP para injetar..."
        kubectl -n "$NS_APP" rollout restart deploy || true
    fi
else
    echo "Namespace $NS_APP ainda nao existe -- suba a aplicacao DEPOIS do agente."
fi

# ---- 3. o dado esta chegando? -----------------------------------------------
COLETOR=$(kubectl -n "$NAMESPACE" get statefulset -o name 2>/dev/null \
          | grep otel-collector | head -1 || true)

if [[ -z "$COLETOR" ]]; then
    echo "Sem coletor OTLP neste cluster (telemetryIngest desligado)."
else
    echo "Conferindo a entrega em $COLETOR (ultimos 10 min)..."
    DESCARTES=$(kubectl -n "$NAMESPACE" logs "$COLETOR" --since=10m 2>/dev/null \
                | grep "Dropping data" | tail -2 || true)
    if [[ -z "$DESCARTES" ]]; then
        echo "  OK: nenhum descarte. O dado esta chegando ao Dynatrace."
    else
        echo "  ATENCAO: o coletor esta DESCARTANDO dado."
        echo "$DESCARTES" \
          | sed 's/.*"otelcol.signal": "\([a-z]*\)".*"error": "\([^"]*\)".*"dropped_items": \([0-9]*\).*/    \1: \3 descartados -- \2/' \
          | cut -c1-180
        echo
        echo "  Se o motivo citar 'storage:internal:write', o token de"
        echo "  ingestao existe mas nao tem escopo. Confira o TIPO antes de"
        echo "  trocar -- dt0s16. ja' e' token de plataforma, e trocar por"
        echo "  outro do mesmo tipo nao resolve:"
        echo "    kubectl -n $NAMESPACE get secret <secret> \\"
        echo "      -o jsonpath='{.data.dataIngestToken}' | base64 -d | cut -c1-7"
        echo "  O caminho e' editar os escopos do token no Dynatrace e so'"
        echo "  entao atualizar o secret e reiniciar o coletor."
    fi
fi

echo "=========================================="
echo " Pos-instalacao concluida"
echo "=========================================="
