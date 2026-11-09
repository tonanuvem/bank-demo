#!/usr/bin/env bash
# =============================================================================
# LAB 3 -- sobe o FIAP OTEL BANK no Kubernetes, atras do Istio
# =============================================================================
#   bash k8s/run-lab-k8s.sh              sobe tudo
#   bash k8s/run-lab-k8s.sh --sem-istio  so' a aplicacao (para comparar depois)
#   bash k8s/run-lab-k8s.sh --urls       so' reimprime os enderecos
#
# PRE-REQUISITOS (nao sao feitos aqui, vem dos scripts do ambiente do LAB):
#   - cluster no ar          kubectl get nodes
#   - Istio instalado        kubectl -n istio-system get deploy istiod
#
# O Dynatrace NAO entra aqui de proposito: a instalacao dele e' um passo da
# aula, com tela e token, nao um detalhe de script. Ver k8s/dynatrace/README.md
# =============================================================================
set -uo pipefail

NS=fiap-bank
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COM_ISTIO=1

for arg in "$@"; do
    case "$arg" in
      --sem-istio) COM_ISTIO=0 ;;
      --urls)      MOSTRAR_URLS_APENAS=1 ;;
    esac
done

titulo() { echo; echo "  $*"; echo "  ${*//?/-}"; }
erro()   { echo "  ERRO: $*" >&2; exit 1; }
aviso()  { echo "  aviso: $*" >&2; }

# ---- descobre por onde o navegador do aluno entra ---------------------------
# Tres caminhos, do mais provavel ao menos, porque isso muda entre o cluster
# kubeadm na EC2 (NodePort + IP publico) e o EKS (LoadBalancer).
descobrir_entrada() {
    local porta ip host

    porta=$(kubectl -n istio-system get svc istio-ingressgateway \
            -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null)
    [ -z "$porta" ] && porta=$(kubectl -n istio-system get svc istio-ingressgateway \
            -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)

    host=$(kubectl -n istio-system get svc istio-ingressgateway \
           -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    ip=$(kubectl -n istio-system get svc istio-ingressgateway \
         -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

    if [ -n "$host" ]; then echo "http://$host"; return; fi
    if [ -n "$ip" ];   then echo "http://$ip";   return; fi

    # NodePort: precisa do IP PUBLICO da maquina, nao do IP do no' (que e'
    # privado na VPC). O ambiente do LAB expoe isso pelo comando `ip`.
    local publico
    publico=$( (cd ~ && ./ip 2>/dev/null) | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    [ -z "$publico" ] && publico=$(kubectl get nodes \
        -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
    [ -z "$publico" ] && publico="IP_EXTERNO"

    [ -n "$porta" ] && echo "http://$publico:$porta" || echo ""
}

mostrar_urls() {
    local entrada; entrada=$(descobrir_entrada)
    titulo "ENDERECOS DO LAB"
    if [ -z "$entrada" ] || [[ "$entrada" == *IP_EXTERNO* ]]; then
        aviso "nao consegui montar a URL automaticamente."
        echo "  Pegue a porta:  kubectl -n istio-system get svc istio-ingressgateway"
        echo "  E o IP:         ./ip"
    else
        echo "  FIAP Bank        $entrada"
        echo "  login            teste@teste.com / Teste@123"
    fi
    echo
    echo "  Kiali            kubectl -n istio-system port-forward svc/kiali 20001:20001"
    echo "  Dynatrace        https://<SEU-AMBIENTE>.apps.dynatrace.com"
    echo
}

[ "${MOSTRAR_URLS_APENAS:-0}" = 1 ] && { mostrar_urls; exit 0; }

# ---- checagens que evitam 20 min de diagnostico na aula ---------------------
command -v kubectl >/dev/null || erro "kubectl nao encontrado"
kubectl get nodes >/dev/null 2>&1 || erro "sem cluster. Rode antes os scripts de criacao do cluster."

if [ "$COM_ISTIO" = 1 ]; then
    kubectl -n istio-system get deploy istiod >/dev/null 2>&1 \
        || erro "Istio nao instalado. Rode o k8s_config_istio_nodeport.sh do ambiente do LAB."
fi

titulo "1/4  NAMESPACE E CONFIGURACAO"
kubectl apply -f "$BASE/app/00-namespace.yaml"

titulo "2/4  APLICACAO"
kubectl apply -f "$BASE/app/10-mongodb.yaml"
kubectl apply -f "$BASE/app/20-backends.yaml"
kubectl apply -f "$BASE/app/30-node-services.yaml"
kubectl apply -f "$BASE/app/40-dashboard-ui.yaml"
kubectl apply -f "$BASE/app/50-transactions-v2.yaml"

# A carga sobe JUNTO, nao depois. O Davis precisa de 30-40 min de linha de
# base antes do game day; se ela so' comecar na hora do caos, nao ha baseline
# e nenhum problema e' aberto.
kubectl apply -f "$BASE/app/90-carga.yaml"

if [ "$COM_ISTIO" = 1 ]; then
    titulo "3/4  MALHA"
    kubectl apply -f "$BASE/istio/00-gateway.yaml"
    kubectl apply -f "$BASE/istio/10-transactions-subsets.yaml"
    kubectl apply -f "$BASE/istio/20-canary.yaml"
    rm -f "$BASE/.estado/caos.env"   # comeca sempre do zero
else
    titulo "3/4  MALHA (pulada por --sem-istio)"
fi

titulo "4/4  AGUARDANDO OS PODS"
echo "  (o primeiro deploy baixa ~7 imagens; de 2 a 5 min)"
for d in mongodb accounts transactions-v1 transactions-v2 loan customer-auth atm-locator dashboard ui carga-fundo; do
    if kubectl -n "$NS" rollout status "deploy/$d" --timeout=240s >/dev/null 2>&1; then
        echo "  ok    $d"
    else
        aviso "$d nao ficou pronto -- veja: kubectl -n $NS describe deploy/$d"
    fi
done

# ---- origem unica: conta a UI por onde as APIs atendem ----------------------
# Quem chama as APIs e' o NAVEGADOR, nao o cluster. Sem este passo a UI
# continua tentando host:5000 / host:8000 / host:8001, que nao existem aqui,
# e o login falha SEM NENHUM log do lado servidor -- a requisicao nunca chega.
if [ "$COM_ISTIO" = 1 ]; then
    ENTRADA=$(descobrir_entrada)
    if [ -n "$ENTRADA" ] && [[ "$ENTRADA" != *IP_EXTERNO* ]]; then
        kubectl -n "$NS" set env deploy/ui FIAP_API_BASE="$ENTRADA" >/dev/null
        kubectl -n "$NS" rollout status deploy/ui --timeout=120s >/dev/null 2>&1
        echo "  ok    ui apontada para $ENTRADA"
    else
        aviso "nao descobri a URL de entrada -- a UI pode nao conseguir chamar as APIs."
        aviso "corrija com: kubectl -n $NS set env deploy/ui FIAP_API_BASE=http://IP:PORTA"
    fi
fi

# ---- conferencia do sidecar -------------------------------------------------
if [ "$COM_ISTIO" = 1 ]; then
    SEM_SIDECAR=$(kubectl -n "$NS" get pods \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{"\n"}{end}' \
        2>/dev/null | grep -v istio-proxy | grep -v '^mongodb' | wc -l | tr -d ' ')
    if [ "${SEM_SIDECAR:-0}" -gt 0 ]; then
        aviso "$SEM_SIDECAR pod(s) sem sidecar do Envoy."
        aviso "o rotulo istio-injection nao e' retroativo. Corrija com:"
        aviso "  kubectl -n $NS rollout restart deploy"
    fi
fi

mostrar_urls
cat <<EOF
  PROXIMOS PASSOS

  1. A carga ja' esta rodando (deployment carga-fundo, 3 replicas).
     Confira que ela esta gerando trafego de verdade:

       kubectl -n $NS logs -l app=carga-fundo --tail=5
       kubectl -n $NS get pods

  2. Instale o Dynatrace:  cat k8s/dynatrace/README.md

  3. DEIXE RODANDO 30-40 MINUTOS antes do game day. E' o tempo de que o
     Davis precisa para saber como e' o normal deste sistema. Use esse
     intervalo para os blocos 1 e 2 do roteiro (cluster e malha), que nao
     dependem do Dynatrace.

  4. So' entao:  bash k8s/caos.sh status

