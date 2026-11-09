#!/usr/bin/env bash
# =============================================================================
# LAB 3 -- injeta falha e divide carga PELA MALHA, sem tocar na aplicacao
# =============================================================================
#   bash k8s/caos.sh status              o que esta ativo agora
#   bash k8s/caos.sh delay 7s 50         50% das chamadas esperam 7s (responde 200)
#   bash k8s/caos.sh abort 503 20        20% das chamadas recebem 503 do Envoy
#   bash k8s/caos.sh canary 20           manda 20% do trafego para a v2 degradada
#   bash k8s/caos.sh retry on|off        3 tentativas por chamada
#   bash k8s/caos.sh resiliencia on|off  circuit breaker (outlierDetection)
#   bash k8s/caos.sh limpar              volta tudo ao normal: 100% v1, sem falha
#
# IRMAO DO deploy.sh DA AULA 2: la' a falha entrava por variavel de ambiente,
# dentro do container. Aqui ela entra no sidecar, fora do container. Mesmos
# sintomas, origens diferentes -- e a aula e' justamente aprender a
# distinguir uma da outra olhando as telas.
# =============================================================================
set -uo pipefail

NS=fiap-bank
ESTADO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.estado"
ENV_CAOS="$ESTADO/caos.env"
mkdir -p "$ESTADO"

# ---- estado corrente (tudo desligado por padrao) ----------------------------
TIPO_FALHA=""      # delay | abort | ""
VALOR_FALHA=""     # 7s    | 503   | ""
PCT_FALHA="0"
PESO_V2="0"
RETRY="off"
[ -f "$ENV_CAOS" ] && . "$ENV_CAOS"

salvar() {
    cat > "$ENV_CAOS" <<EOF
TIPO_FALHA="$TIPO_FALHA"
VALOR_FALHA="$VALOR_FALHA"
PCT_FALHA="$PCT_FALHA"
PESO_V2="$PESO_V2"
RETRY="$RETRY"
EOF
}

erro() { echo "  ERRO: $*" >&2; exit 1; }

checar_cluster() {
    kubectl get ns "$NS" >/dev/null 2>&1 \
        || erro "namespace $NS nao existe. Rode antes: bash k8s/run-lab-k8s.sh"
    kubectl -n "$NS" get virtualservice transactions >/dev/null 2>&1 \
        || erro "VirtualService 'transactions' nao existe. Rode: bash k8s/run-lab-k8s.sh"
}

# ---- monta e aplica o VirtualService a partir do estado ---------------------
aplicar() {
    local peso_v1=$((100 - PESO_V2))
    local bloco_falha="" bloco_retry=""

    if [ -n "$TIPO_FALHA" ] && [ "$PCT_FALHA" != "0" ]; then
        case "$TIPO_FALHA" in
          delay)
            bloco_falha=$(printf '%s\n' \
              "      fault:" \
              "        delay:" \
              "          percentage: { value: $PCT_FALHA }" \
              "          fixedDelay: $VALOR_FALHA")
            ;;
          abort)
            bloco_falha=$(printf '%s\n' \
              "      fault:" \
              "        abort:" \
              "          percentage: { value: $PCT_FALHA }" \
              "          httpStatus: $VALOR_FALHA")
            ;;
        esac
    fi

    if [ "$RETRY" = "on" ]; then
        bloco_retry=$(printf '%s\n' \
          "      retries:" \
          "        attempts: 3" \
          "        perTryTimeout: 2s" \
          "        retryOn: 5xx,reset,connect-failure")
    fi

    # Um VirtualService SO' para o host transactions. Dois objetos para o mesmo
    # host entram em conflito silencioso -- por isso tudo e' reescrito aqui.
    {
        echo "apiVersion: networking.istio.io/v1"
        echo "kind: VirtualService"
        echo "metadata:"
        echo "  name: transactions"
        echo "  namespace: $NS"
        echo "spec:"
        echo "  hosts: [transactions]"
        echo "  http:"
        echo "    - route:"
        echo "        - destination: { host: transactions, subset: v1 }"
        echo "          weight: $peso_v1"
        echo "        - destination: { host: transactions, subset: v2 }"
        echo "          weight: $PESO_V2"
        [ -n "$bloco_falha" ] && echo "$bloco_falha"
        [ -n "$bloco_retry" ] && echo "$bloco_retry"
    } | kubectl apply -f - >/dev/null || erro "kubectl apply falhou"

    salvar
}

# ---- o que esta no ar -------------------------------------------------------
cmd_status() {
    checar_cluster
    local peso_v1=$((100 - PESO_V2))
    echo
    echo "  ESTADO DA MALHA -- servico transactions"
    echo "  ---------------------------------------"
    printf "  trafego          v1 %s%%   v2 %s%%\n" "$peso_v1" "$PESO_V2"
    if [ -n "$TIPO_FALHA" ] && [ "$PCT_FALHA" != "0" ]; then
        printf "  falha injetada   %s %s em %s%% das chamadas\n" \
               "$TIPO_FALHA" "$VALOR_FALHA" "$PCT_FALHA"
    else
        echo   "  falha injetada   nenhuma"
    fi
    printf "  retry            %s\n" "$RETRY"
    if kubectl -n "$NS" get destinationrule transactions -o yaml 2>/dev/null \
       | grep -q outlierDetection; then
        echo "  circuit breaker  ligado"
    else
        echo "  circuit breaker  desligado"
    fi
    echo
    echo "  Conferir pelo proprio Istio:"
    echo "    kubectl -n $NS get virtualservice transactions -o yaml"
    echo
}

cmd_delay() {
    local dur="${1:-7s}" pct="${2:-50}"
    [[ "$dur" =~ ^[0-9]+(ms|s)$ ]] || erro "duracao invalida: '$dur' (use 7s ou 1400ms)"
    [[ "$pct" =~ ^[0-9]+$ ]] && [ "$pct" -le 100 ] || erro "percentual invalido: '$pct'"
    checar_cluster
    TIPO_FALHA=delay; VALOR_FALHA="$dur"; PCT_FALHA="$pct"
    aplicar
    cat <<EOF

  ATRASO ATIVO -- $pct% das chamadas a transactions esperam $dur

  A aplicacao nao sabe de nada: o Envoy segura a requisicao ANTES de
  entregar ao processo. Todas respondem 200.

  O que procurar, nesta ordem:
    1. taxa de erro         deve ficar em ZERO. O mapa continua verde.
    2. SLO de latencia      comeca a queimar; o de disponibilidade, nao.
    3. volume de negocio    transferencias/min CAI -- o usuario desiste.
    4. log do pod           abra e constate: nao ha nada la'.

  Cronometre: quanto tempo ate o Davis abrir um problema?

  Proximo:  bash k8s/caos.sh abort 503 20
EOF
}

cmd_abort() {
    local http="${1:-503}" pct="${2:-20}"
    [[ "$http" =~ ^[45][0-9][0-9]$ ]] || erro "status invalido: '$http' (use 500, 503...)"
    [[ "$pct" =~ ^[0-9]+$ ]] && [ "$pct" -le 100 ] || erro "percentual invalido: '$pct'"
    checar_cluster
    TIPO_FALHA=abort; VALOR_FALHA="$http"; PCT_FALHA="$pct"
    aplicar
    cat <<EOF

  ERRO ATIVO -- $pct% das chamadas a transactions recebem HTTP $http

  O 503 sai do sidecar. O processo nunca foi chamado: sem excecao, sem
  stack trace, sem linha no log da aplicacao.

  O que procurar:
    1. CRONOMETRE ate o card do Davis aparecer. Compare com o tempo que
       voce levou para achar o mesmo sintoma no Grafana da aula 2.
    2. O Davis aponta uma causa. Ele acerta? O que ele diria se soubesse
       que a falha esta no sidecar e nao no processo?
    3. Error Budget: em quantos minutos o orcamento acaba neste ritmo?

  Para ver a malha se curando:  bash k8s/caos.sh resiliencia on
  Para limpar:                  bash k8s/caos.sh limpar
EOF
}

cmd_canary() {
    local pct="${1:-20}"
    [[ "$pct" =~ ^[0-9]+$ ]] && [ "$pct" -le 100 ] || erro "percentual invalido: '$pct'"
    checar_cluster
    kubectl -n "$NS" get deploy transactions-v2 >/dev/null 2>&1 \
        || erro "transactions-v2 nao existe. Rode: kubectl apply -f k8s/app/50-transactions-v2.yaml"
    PESO_V2="$pct"
    aplicar
    cat <<EOF

  CANARY -- $pct% do trafego vai para a v2 (a versao degradada: +1,4s e 15% de erro)

  Esta e' a MESMA v1.3.0 da aula 2. A diferenca e' que la' ela foi para
  100% dos usuarios de uma vez.

  As tres perguntas:
    1. O Davis abre problema mesmo com so' $pct% afetado?
    2. O Error Budget queima mais devagar? Em que proporcao?
    3. $pct% de usuarios atingidos e' um preco aceitavel para descobrir
       que a versao esta ruim? Qual seria esse numero na B3?

  Voltar atras:  bash k8s/caos.sh canary 0
EOF
}

cmd_retry() {
    case "${1:-}" in
      on|off) RETRY="$1" ;;
      *) erro "use: caos.sh retry on|off" ;;
    esac
    checar_cluster
    aplicar
    if [ "$RETRY" = on ]; then
        cat <<EOF

  RETRY LIGADO -- 3 tentativas, 2s cada

  Olhe o descolamento: o CLIENTE passa a ver sucesso e o SLO de
  disponibilidade volta ao verde, enquanto o servico de tras continua
  errando na mesma taxa. A verdade migrou da taxa de erro para a
  latencia e para a contagem de chamadas.

  E o risco: 3 tentativas num servico sobrecarregado triplicam a carga
  exatamente quando ele menos aguenta. E' assim que um incidente pequeno
  vira um apagao.
EOF
    else
        echo; echo "  Retry desligado."; echo
    fi
}

cmd_resiliencia() {
    checar_cluster
    case "${1:-}" in
      on)
        kubectl apply -f "$(dirname "${BASH_SOURCE[0]}")/istio/40-resiliencia.yaml" >/dev/null \
            || erro "kubectl apply falhou"
        cat <<EOF

  CIRCUIT BREAKER LIGADO (outlierDetection)

  Com a falha ainda ativa, a taxa de erro deve CAIR em menos de 1 minuto
  sem ninguem ter corrigido nada: o Envoy tira do balanceamento o pod que
  errou 5 vezes seguidas.

  Pergunta: maxEjectionPercent esta em 50. Por que nao 100?
  (Dica: pense num Mongo fora do ar, com TODOS os pods errando ao mesmo tempo.)
EOF
        ;;
      off)
        kubectl apply -f "$(dirname "${BASH_SOURCE[0]}")/istio/10-transactions-subsets.yaml" >/dev/null \
            || erro "kubectl apply falhou"
        echo; echo "  Circuit breaker desligado (DestinationRule voltou ao basico)."; echo
        ;;
      *) erro "use: caos.sh resiliencia on|off" ;;
    esac
}

cmd_limpar() {
    checar_cluster
    TIPO_FALHA=""; VALOR_FALHA=""; PCT_FALHA="0"; PESO_V2="0"; RETRY="off"
    aplicar
    kubectl apply -f "$(dirname "${BASH_SOURCE[0]}")/istio/10-transactions-subsets.yaml" >/dev/null 2>&1
    cat <<EOF

  MALHA LIMPA -- 100% v1, sem falha, sem retry, sem circuit breaker

  Deixe a carga rodando mais 5 minutos antes de encerrar: o Davis precisa
  ver o sistema saudavel de novo para FECHAR o problema. Um problema que
  fecha sozinho e' evidencia no postmortem -- mostra a hora exata em que
  o impacto cessou.
EOF
}

case "${1:-status}" in
  status)      cmd_status ;;
  delay)       shift; cmd_delay "$@" ;;
  abort)       shift; cmd_abort "$@" ;;
  canary)      shift; cmd_canary "$@" ;;
  retry)       shift; cmd_retry "$@" ;;
  resiliencia) shift; cmd_resiliencia "$@" ;;
  limpar)      cmd_limpar ;;
  *) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
esac
