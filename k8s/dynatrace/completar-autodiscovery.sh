#!/usr/bin/env bash
# =============================================================================
# Complemento ao Auto Discovery do Dynatrace
# =============================================================================
# O caminho do Auto Discovery (quatro linhas com dtwiz) e' o mais rapido para
# por o cluster no ar, e e' o que este laboratorio usa. Mas ele para antes de
# tres coisas, e as tres so' aparecem quando voce vai procurar o dado e ele
# nao esta la':
#
#   1. O token de ingestao nao tem escopo para OTLP. O coletor RECEBE os spans
#      e e' recusado na entrega: "Access token is missing required scope. Use
#      one of: [storage:internal:write]". Nenhum pod da aplicacao registra
#      nada -- quem sabe que o dado foi jogado fora e' so' o coletor.
#   2. A injecao de code module NAO e' retroativa. Pod que ja' estava rodando
#      quando o DynaKube ficou pronto continua sem instrumentacao, para
#      sempre. A propria tela do assistente avisa isso em letra miuda.
#   3. O assistente instala applicationMonitoring, nao cloudNativeFullStack:
#      voce tem servico e trace, e nao tem a camada de host e processo no
#      Smartscape.
#
# Este script e' IDEMPOTENTE e, por padrao, SO' DIAGNOSTICA. Cada correcao
# exige uma flag, e cada uma e' um unico kubectl patch, reversivel.
#
#   bash completar-autodiscovery.sh                    diagnostica e sai
#   bash completar-autodiscovery.sh --corrigir-token   usa $DT_PLATFORM_TOKEN
#   bash completar-autodiscovery.sh --fullstack        applicationMonitoring -> cloudNativeFullStack
#   bash completar-autodiscovery.sh --reinjetar fiap-bank
#
# Ele NAO toca no DynaKube principal: isso e' trabalho do dynatrace-config.sh,
# que ajusta AppArmor e ActiveGate. Os dois se complementam, nao se repetem.
# =============================================================================
set -uo pipefail

NS=dynatrace
CORRIGIR_TOKEN=0
FULLSTACK=0
REINJETAR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --corrigir-token) CORRIGIR_TOKEN=1 ;;
        --fullstack)      FULLSTACK=1 ;;
        --reinjetar)      REINJETAR="${2:-}"; shift ;;
        -h|--help)        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "opcao desconhecida: $1"; exit 1 ;;
    esac
    shift
done

titulo() { echo; echo "  $*"; echo "  ${*//?/-}"; }
aviso()  { echo "  aviso: $*" >&2; }

kubectl get ns "$NS" >/dev/null 2>&1 || { echo "namespace $NS nao existe -- rode o Auto Discovery antes."; exit 1; }

# ---- o que cada DynaKube liga ----------------------------------------------
titulo "DYNAKUBES"
kubectl -n "$NS" get dynakube -o jsonpath='{range .items[*]}  {.metadata.name}{"\n    oneAgent: "}{.spec.oneAgent}{"\n    logs: "}{.spec.logMonitoring}{"\n    telemetryIngest: "}{.spec.telemetryIngest.serviceName}{"\n"}{end}' 2>/dev/null

# O DynaKube de agentes e' o que tem oneAgent; o principal so' monitora o
# cluster. O nome varia conforme o assistente, entao descobrimos em vez de
# assumir "kubernetes-agents".
DK_AGENTES=$(kubectl -n "$NS" get dynakube \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.oneAgent}{"\n"}{end}' 2>/dev/null \
    | awk 'NF>1 {print $1; exit}')
[ -z "$DK_AGENTES" ] && aviso "nenhum DynaKube com oneAgent -- a aplicacao nao vai ter trace."

# ---- o coletor esta entregando ou descartando? ------------------------------
titulo "COLETOR OTLP"
COLETOR=$(kubectl -n "$NS" get statefulset -o name 2>/dev/null | grep otel-collector | head -1)
if [ -z "$COLETOR" ]; then
    echo "  nao ha coletor OTLP neste cluster (telemetryIngest desligado)."
else
    echo "  $COLETOR"
    ERROS=$(kubectl -n "$NS" logs "$COLETOR" --since=10m 2>/dev/null | grep "Dropping data" | tail -4)
    if [ -z "$ERROS" ]; then
        echo "  nenhum descarte nos ultimos 10 min -- o dado esta chegando."
    else
        aviso "o coletor esta DESCARTANDO dado. Motivo, direto do log:"
        echo "$ERROS" | sed 's/.*"otelcol.signal": "\([a-z]*\)".*"error": "\([^"]*\)".*"dropped_items": \([0-9]*\).*/    \1: \3 descartados -- \2/' | cut -c1-200
    fi
fi

# ---- quantos pods da aplicacao tem o code module ----------------------------
if [ -n "$REINJETAR" ]; then
    titulo "INJECAO EM $REINJETAR"
    TOTAL=$(kubectl -n "$REINJETAR" get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
    COM=$(kubectl -n "$REINJETAR" get pods \
          -o jsonpath='{range .items[*]}{.spec.initContainers[*].name}{"\n"}{end}' 2>/dev/null \
          | grep -c dynatrace)
    echo "  $COM de $TOTAL pod(s) com o code module injetado"
fi

# =============================================================================
# CORRECOES -- cada uma so' acontece com a flag
# =============================================================================

# 1. Token de ingestao. O Auto Discovery ja' exporta DT_PLATFORM_TOKEN no seu
#    terminal; reaproveitamos esse mesmo token em vez de gerar outro. E' o
#    token de plataforma que carrega os escopos storage:*, que sao os que o
#    endpoint OTLP exige.
if [ "$CORRIGIR_TOKEN" = 1 ]; then
    titulo "CORRIGINDO O TOKEN DE INGESTAO"
    if [ -z "${DT_PLATFORM_TOKEN:-}" ]; then
        aviso "DT_PLATFORM_TOKEN nao esta no ambiente."
        aviso "e' a mesma variavel que a tela de Auto Discovery mandou exportar:"
        aviso "  export DT_PLATFORM_TOKEN=\"dt0s16...\""
        exit 1
    fi
    SECRET=$(kubectl -n "$NS" get dynakube "$DK_AGENTES" -o jsonpath='{.spec.tokens}' 2>/dev/null)
    [ -z "$SECRET" ] && SECRET="$DK_AGENTES"
    echo "  secret: $SECRET  (chave dataIngestToken)"
    if kubectl -n "$NS" patch secret "$SECRET" --type=merge \
         -p "{\"stringData\":{\"dataIngestToken\":\"$DT_PLATFORM_TOKEN\"}}" >/dev/null 2>&1; then
        echo "  token substituido"
        [ -n "$COLETOR" ] && kubectl -n "$NS" rollout restart "$COLETOR" >/dev/null 2>&1 \
            && echo "  coletor reiniciado -- confira o descarte daqui a 1 min rodando este script de novo"
    else
        aviso "nao consegui alterar o secret $SECRET."
    fi
fi

# 2. Full-stack. Troca applicationMonitoring por cloudNativeFullStack, que e' o
#    que acrescenta a camada de host e processo no Smartscape -- a perna que
#    falta na cadeia aplicacao -> servico -> processo -> host.
#    CUSTO: sobe um DaemonSet de OneAgent, com consumo de memoria por no'.
if [ "$FULLSTACK" = 1 ]; then
    titulo "MIGRANDO PARA CLOUDNATIVEFULLSTACK"
    MODO=$(kubectl -n "$NS" get dynakube "$DK_AGENTES" -o jsonpath='{.spec.oneAgent}' 2>/dev/null)
    case "$MODO" in
        *cloudNativeFullStack*) echo "  ja' esta em cloudNativeFullStack -- nada a fazer." ;;
        *applicationMonitoring*)
            if kubectl -n "$NS" patch dynakube "$DK_AGENTES" --type=json -p \
               '[{"op":"remove","path":"/spec/oneAgent/applicationMonitoring"},{"op":"add","path":"/spec/oneAgent/cloudNativeFullStack","value":{}}]' >/dev/null 2>&1; then
                echo "  migrado. O DaemonSet do OneAgent sobe em seguida."
                echo "  para voltar: troque de volta por applicationMonitoring: {}"
            else
                aviso "o patch falhou -- veja o spec com kubectl -n $NS get dynakube $DK_AGENTES -o yaml"
            fi ;;
        *) aviso "oneAgent em formato inesperado: $MODO" ;;
    esac
fi

# 3. Reinjecao. A injecao acontece no webhook, na CRIACAO do pod. Quem ja'
#    estava rodando nao ganha code module sozinho -- nunca.
if [ -n "$REINJETAR" ]; then
    titulo "REINJETANDO EM $REINJETAR"
    if kubectl -n "$REINJETAR" rollout restart deploy >/dev/null 2>&1; then
        echo "  rollout restart disparado em todos os Deployments"
        echo "  acompanhe: kubectl -n $REINJETAR rollout status deploy --timeout=300s"
    else
        aviso "nao consegui reiniciar os Deployments de $REINJETAR"
    fi
fi

echo
echo "  Rode sem flag nenhuma depois de cada correcao: o diagnostico e' o"
echo "  unico jeito de saber se o dado passou a chegar. Pod saudavel nao"
echo "  prova entrega -- foi assim que 729 spans foram descartados aqui sem"
echo "  uma linha de erro na aplicacao."
echo
