#!/usr/bin/env bash
# =============================================================================
# Complemento ao Auto Discovery do Dynatrace
# =============================================================================
# O caminho do Auto Discovery (quatro linhas com dtwiz) e' o mais rapido para
# por o cluster no ar, e e' o que este laboratorio usa. Mas ele para antes de
# tres coisas, e as tres so' aparecem quando voce vai procurar o dado e ele
# nao esta la':
#
#   1. O coletor RECEBE os spans e e' recusado na entrega pelo ActiveGate:
#      403 em traces, 401 em metrics. Nenhum pod da aplicacao registra nada --
#      quem sabe que o dado foi jogado fora e' so' o coletor.
#      ATENCAO ao diagnostico: a mensagem fala em escopo de token
#      ("storage:internal:write"), e nao era. Testado aqui, o MESMO token
#      respondia 200 nos tres endpoints direto no tenant. A causa era a
#      VERSAO DO ACTIVEGATE do DynaKube de agentes, varias versoes atras da
#      do principal -- veja a secao de imagem abaixo.
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
ALINHAR=0
FULLSTACK=0
REINJETAR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --corrigir-token) CORRIGIR_TOKEN=1 ;;
        --alinhar-imagem) ALINHAR=1 ;;
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

# ---- as imagens de ActiveGate batem entre os DynaKube? ----------------------
# O coletor OTLP entrega atraves do ActiveGate do DynaKube de agentes. Se esse
# ActiveGate estiver numa versao mais velha que a do principal -- o que
# acontece quando um script fixa a imagem so' do principal -- a entrega e'
# recusada com uma mensagem que parece falar de token.
titulo "IMAGENS DO ACTIVEGATE"
kubectl -n "$NS" get dynakube -o jsonpath='{range .items[*]}  {.metadata.name}{" -> "}{.spec.activeGate.image}{"\n"}{end}' 2>/dev/null
IMGS=$(kubectl -n "$NS" get dynakube -o jsonpath='{range .items[*]}{.spec.activeGate.image}{"\n"}{end}' 2>/dev/null | grep -v '^$' | sort -u | wc -l | tr -d ' ')
if [ "${IMGS:-0}" -gt 1 ]; then
    aviso "os DynaKube estao em versoes DIFERENTES de ActiveGate."
    aviso "e' a causa mais provavel de descarte no coletor. Alinhe com:"
    aviso "  bash $0 --alinhar-imagem"
fi

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
# Testa um token contra o endpoint OTLP do tenant SEM alterar nada. Corpo
# vazio de proposito: o que interessa e' o codigo de autorizacao, nao o
# conteudo. 401/403 = token sem escopo; 400 = token aceito e payload
# invalido, que para este teste e' sucesso.
testar_token() {   # testar_token <ambiente> <token>
    local amb="${1%/}" tok="$2" codigo
    amb="${amb%/api}"
    # O Auto Discovery exporta DT_ENVIRONMENT com o dominio .apps, que e' a
    # interface; a ingestao vive no .live. Sem esta troca o teste bate numa
    # URL que nao existe e devolve 404, parecendo problema de token.
    amb="${amb/.apps.dynatrace.com/.live.dynatrace.com}"
    codigo=$(curl -s -o /dev/null -m 20 -w '%{http_code}' -X POST \
        "$amb/api/v2/otlp/v1/traces" \
        -H "Authorization: Api-Token $tok" \
        -H "Content-Type: application/x-protobuf" \
        --data-binary '' 2>/dev/null)
    echo "$codigo"
}

if [ "$CORRIGIR_TOKEN" = 1 ]; then
    titulo "TOKEN DE INGESTAO"

    # Se o ambiente trouxer o par exportado pelo Auto Discovery, testamos o
    # token ANTES de encostar no secret. Aplicar um token que tambem seria
    # recusado so' troca um problema silencioso por outro.
    if [ -n "${DT_PLATFORM_TOKEN:-}" ]; then
        # O apiUrl do proprio DynaKube e' a fonte mais confiavel do endereco
        # do tenant; DT_ENVIRONMENT entra como segunda opcao.
        AMBIENTE=$(kubectl -n "$NS" get dynakube "$DK_AGENTES" -o jsonpath='{.spec.apiUrl}' 2>/dev/null)
        [ -z "$AMBIENTE" ] && AMBIENTE="${DT_ENVIRONMENT:-}"
        if [ -z "$AMBIENTE" ]; then
            aviso "nao sei o endereco do tenant -- exporte DT_ENVIRONMENT."
            exit 1
        fi
        CODIGO=$(testar_token "$AMBIENTE" "$DT_PLATFORM_TOKEN")
        echo "  teste do DT_PLATFORM_TOKEN contra o endpoint OTLP: HTTP $CODIGO"
        case "$CODIGO" in
            400|200|204) echo "  o token E' ACEITO -- segue para aplicar no secret." ;;
            401|403)
                aviso "este token tambem seria recusado (HTTP $CODIGO)."
                aviso "nao adianta aplicar: edite os escopos no Dynatrace antes."
                aviso "  storage:internal:write / openTelemetryTrace.ingest / metrics.ingest / logs.ingest"
                exit 1 ;;
            000) aviso "nao consegui falar com $DT_ENVIRONMENT -- sem rede ou URL errada." ; exit 1 ;;
            *)   aviso "resposta inesperada ($CODIGO); seguindo mesmo assim." ;;
        esac
    fi
    SECRET=$(kubectl -n "$NS" get dynakube "$DK_AGENTES" -o jsonpath='{.spec.tokens}' 2>/dev/null)
    [ -z "$SECRET" ] && SECRET="$DK_AGENTES"

    # Antes de trocar, olhe o que ja' esta la'. O prefixo diz o TIPO:
    #   dt0s16.  token de plataforma (escopos storage:*, openPipeline:*, ...)
    #   dt0c01.  token de API classico (escopos metrics.ingest, logs.ingest, ...)
    TIPO=$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.dataIngestToken}' 2>/dev/null \
           | base64 -d 2>/dev/null | cut -c1-7)
    echo "  secret: $SECRET  (chave dataIngestToken, tipo $TIPO)"

    if [ "$TIPO" = "dt0s16." ]; then
        echo
        echo "  JA' E' UM TOKEN DE PLATAFORMA. Trocar por outro do mesmo tipo"
        echo "  nao resolve: o que falta nao e' o tipo, e' o ESCOPO."
        echo
        echo "  No Dynatrace, em Settings -> Platform tokens, edite este token"
        echo "  (ou crie outro) com os escopos que o proprio erro nomeia:"
        echo "      storage:internal:write      <- traces, e' o 403"
        echo "      openTelemetryTrace.ingest"
        echo "      metrics.ingest"
        echo "      logs.ingest"
        echo
        echo "  Depois, com o token novo em maos:"
        echo "      kubectl -n $NS patch secret $SECRET --type=merge \\"
        echo "        -p '{\"stringData\":{\"dataIngestToken\":\"dt0s16...\"}}'"
        echo "      kubectl -n $NS rollout restart $COLETOR"
        exit 0
    fi

    if [ -z "${DT_PLATFORM_TOKEN:-}" ]; then
        aviso "o token atual e' do tipo $TIPO e DT_PLATFORM_TOKEN nao esta no ambiente."
        aviso "e' a mesma variavel que a tela de Auto Discovery mandou exportar."
        exit 1
    fi
    if kubectl -n "$NS" patch secret "$SECRET" --type=merge \
         -p "{\"stringData\":{\"dataIngestToken\":\"$DT_PLATFORM_TOKEN\"}}" >/dev/null 2>&1; then
        echo "  token de plataforma aplicado no lugar do $TIPO"
        [ -n "$COLETOR" ] && kubectl -n "$NS" rollout restart "$COLETOR" >/dev/null 2>&1 \
            && echo "  coletor reiniciado -- rode este script de novo daqui a 1 min"
    else
        aviso "nao consegui alterar o secret $SECRET."
    fi
fi

# 1b. Alinha a imagem do ActiveGate do DynaKube de agentes com a do principal.
if [ "$ALINHAR" = 1 ]; then
    titulo "ALINHANDO A IMAGEM DO ACTIVEGATE"
    DK_PRINCIPAL=$(kubectl -n "$NS" get dynakube \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.oneAgent}{"\n"}{end}' 2>/dev/null \
        | awk 'NF==1 {print $1; exit}')
    IMG=$(kubectl -n "$NS" get dynakube "$DK_PRINCIPAL" -o jsonpath='{.spec.activeGate.image}' 2>/dev/null)
    if [ -z "$IMG" ]; then
        aviso "o DynaKube principal nao tem imagem fixada -- nada para copiar."
    else
        echo "  copiando de $DK_PRINCIPAL para $DK_AGENTES:"
        echo "    $IMG"
        kubectl -n "$NS" patch dynakube "$DK_AGENTES" --type=merge \
          -p "{\"spec\":{\"activeGate\":{\"image\":\"$IMG\"}}}" >/dev/null 2>&1 \
          && echo "  aplicado -- aguarde o rollout e reinicie o coletor:" \
          && echo "    kubectl -n $NS rollout status statefulset/${DK_AGENTES}-activegate" \
          && echo "    kubectl -n $NS rollout restart statefulset/${DK_AGENTES}-otel-collector"
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
