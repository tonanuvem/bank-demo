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

# Porta em que o Gateway do banco escuta no ingressgateway, e o nome dessa
# porta no Service (usado para achar o NodePort). O valor pode mudar sozinho:
# ver resolver_porta_gateway().
PORTA_GW=80
NOME_PORTA_SVC=http2
FORCAR_PORTA=0

for arg in "$@"; do
    case "$arg" in
      --sem-istio) COM_ISTIO=0 ;;
      --urls)      MOSTRAR_URLS_APENAS=1 ;;
      --porta=*)   PORTA_GW="${arg#*=}"; NOME_PORTA_SVC=""; FORCAR_PORTA=1 ;;
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

    if [ -n "$NOME_PORTA_SVC" ]; then
        porta=$(kubectl -n istio-system get svc istio-ingressgateway \
                -o jsonpath="{.spec.ports[?(@.name==\"$NOME_PORTA_SVC\")].nodePort}" 2>/dev/null)
    fi
    [ -z "$porta" ] && porta=$(kubectl -n istio-system get svc istio-ingressgateway \
            -o jsonpath="{.spec.ports[?(@.port==$PORTA_GW)].nodePort}" 2>/dev/null)

    host=$(kubectl -n istio-system get svc istio-ingressgateway \
           -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    ip=$(kubectl -n istio-system get svc istio-ingressgateway \
         -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

    # Num LoadBalancer o navegador fala com a porta do Gateway, nao com NodePort.
    local sufixo=""
    [ "$PORTA_GW" != 80 ] && sufixo=":$PORTA_GW"
    if [ -n "$host" ]; then echo "http://$host$sufixo"; return; fi
    if [ -n "$ip" ];   then echo "http://$ip$sufixo";   return; fi

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

# ---- de quem e' a porta 80 do ingressgateway? -------------------------------
# O ambiente do LAB instala o Bookinfo junto com o Istio, e o Gateway dele ja'
# ocupa a porta 80 com hosts ["*"]. Quando dois Gateways declaram a mesma porta
# e o mesmo host, o Istio MESCLA os dois num unico listener e a ordem das rotas
# entre eles nao e' garantida -- o /login (match exato) do Bookinfo passa a
# disputar com a tela de login do banco, e o que quebra muda a cada deploy.
#
# Em vez de apagar o Gateway do ambiente, o banco sai da frente: o profile demo
# ja' expoe a porta 31400 no MESMO ingressgateway, e ela esta livre. O Bookinfo
# continua no ar, o que importa para a demo de Istio do inicio da aula.
resolver_porta_gateway() {
    local dono alt
    [ "$FORCAR_PORTA" = 1 ] && return 0

    # Sem range aninhado: kubectl aceita a sintaxe, nao devolve nada e o
    # 2>/dev/null engole o aviso -- o conflito passava batido e o banco
    # continuava disputando a porta 80 com o Bookinfo.
    dono=$(kubectl get gateways.networking.istio.io -A \
           -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{" "}{.spec.servers[*].port.number}{"\n"}{end}' 2>/dev/null \
           | grep -v "^$NS/" | awk '{for (i=2;i<=NF;i++) if ($i==80) {print $1; exit}}')
    [ -z "$dono" ] && return 0

    alt=$(kubectl -n istio-system get svc istio-ingressgateway \
          -o jsonpath='{range .spec.ports[?(@.port==31400)]}{.name}{end}' 2>/dev/null)
    if [ -n "$alt" ]; then
        PORTA_GW=31400
        NOME_PORTA_SVC="$alt"
        aviso "a porta 80 do ingressgateway ja' e' do Gateway $dono (Bookinfo do ambiente)."
        aviso "o banco vai usar a 31400 do mesmo gateway; o Bookinfo continua funcionando."
    else
        aviso "a porta 80 ja' e' do Gateway $dono e a 31400 nao esta exposta."
        aviso "se o banco nao abrir, libere a porta 80:"
        aviso "  kubectl -n ${dono%%/*} delete gateway ${dono##*/}"
    fi
}

# ---- por que nao injetou o sidecar? -----------------------------------------
# Esta e' a falha que mais custa tempo na aula, e o aviso generico ("o rotulo
# nao e' retroativo") esta certo em um caso so'. Aqui perguntamos ao cluster.
diagnosticar_sidecar() {
    local webhooks bookinfo
    echo
    echo "  DIAGNOSTICO DA INJECAO"
    echo "  ----------------------"

    webhooks=$(kubectl get mutatingwebhookconfiguration \
        -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{.webhooks[*].namespaceSelector}{"\n"}{end}' \
        2>/dev/null | grep -i istio)

    if [ -z "$webhooks" ]; then
        echo "  Nao existe webhook de injecao do Istio neste cluster: o istiod"
        echo "  subiu, mas o sidecar-injector nao. Reinstale o Istio."
        return
    fi

    echo "  webhook de injecao e o rotulo de namespace que ele exige:"
    echo "$webhooks" | sed 's/^/    /'
    echo
    echo "  rotulos que o namespace $NS tem hoje:"
    kubectl get ns "$NS" -o jsonpath='{.metadata.labels}' 2>/dev/null | sed 's/^/    /'
    echo
    echo "  e os do namespace default, onde o ambiente poe o Bookinfo:"
    kubectl get ns default -o jsonpath='{.metadata.labels}' 2>/dev/null | sed 's/^/    /'
    echo
    echo "  Se o webhook exige istio.io/rev (instalacao com revisao), o rotulo"
    echo "  istio-injection=enabled e' ignorado. Nesse caso:"
    echo "    kubectl label ns $NS istio-injection- istio.io/rev=<revisao> --overwrite"
    echo

    bookinfo=$(kubectl -n default get pods \
        -o jsonpath='{range .items[*]}{.spec.initContainers[*].name}{" "}{.spec.containers[*].name}{"\n"}{end}' \
        2>/dev/null | grep -c istio-proxy)
    echo "  pods COM sidecar no namespace default (Bookinfo do ambiente): ${bookinfo:-0}"
    if [ "${bookinfo:-0}" -gt 0 ]; then
        echo "  => a injecao funciona no cluster, so' nao pegou aqui. Reaplique:"
        echo "       kubectl -n $NS rollout restart deploy"
    else
        echo "  => a injecao nao esta funcionando em namespace nenhum. O motivo"
        echo "     aparece no istiod:"
        echo "       kubectl -n istio-system logs deploy/istiod --tail=50 | grep -i inject"
    fi
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
# O gerador de carga ja' se chamou carga-fundo. Um rename em Kubernetes nao
# renomeia nada: cria um objeto novo e deixa o antigo no ar, gerando carga em
# paralelo -- o dobro de trafego na linha de base, e dois nos no Kiali para a
# mesma coisa. Removemos o antigo, se ainda existir.
kubectl -n "$NS" delete deploy,configmap carga-fundo --ignore-not-found >/dev/null 2>&1
kubectl apply -f "$BASE/app/90-stress-carga.yaml"

if [ "$COM_ISTIO" = 1 ]; then
    titulo "3/4  MALHA"
    resolver_porta_gateway
    kubectl apply -f "$BASE/istio/00-gateway.yaml"
    if [ "$PORTA_GW" != 80 ]; then
        kubectl -n "$NS" patch gateway fiap-bank-gateway --type=json \
          -p "[{\"op\":\"replace\",\"path\":\"/spec/servers/0/port/number\",\"value\":$PORTA_GW},{\"op\":\"replace\",\"path\":\"/spec/servers/0/port/name\",\"value\":\"http-fiap\"}]" \
          >/dev/null
    fi
    echo "  gateway do banco na porta $PORTA_GW do istio-ingressgateway"
    kubectl apply -f "$BASE/istio/10-transactions-subsets.yaml"
    kubectl apply -f "$BASE/istio/20-canary.yaml"
    rm -f "$BASE/.estado/caos.env"   # comeca sempre do zero
else
    titulo "3/4  MALHA (pulada por --sem-istio)"
fi

titulo "4/4  AGUARDANDO OS PODS"
echo "  (o primeiro deploy baixa ~7 imagens; de 2 a 5 min)"
for d in mongodb accounts transactions-v1 transactions-v2 loan customer-auth atm-locator dashboard ui stress-carga; do
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

        # A variavel so' tem efeito se a IMAGEM da UI for recente. O
        # entrypoint antigo injeta apenas { dashboard: 5000 } e o bundle
        # antigo nem le "base": o navegador volta a chamar a porta 8000 do
        # host, que nao existe em Kubernetes, e o login falha com
        # "NetworkError when attempting to fetch resource" -- sem log nenhum
        # do lado do servidor, porque a requisicao nao chega. Verificamos
        # servindo o proprio index.html.
        # Lido DENTRO do pod, nao pela URL publica: uma EC2 nao alcanca o
        # proprio IP publico, entao o curl daqui falhava sempre e o aviso
        # aparecia mesmo com a imagem nova.
        INDEX_UI=$(kubectl -n "$NS" exec deploy/ui -- cat /bankapp/index.html 2>/dev/null)
        if [ -z "$INDEX_UI" ]; then
            aviso "nao consegui ler o index.html do pod da ui para conferir a imagem."
        elif ! printf '%s' "$INDEX_UI" | grep -q 'base:'; then
            aviso "a imagem da UI e' anterior ao modo de origem unica."
            aviso "o login vai falhar com NetworkError. Reconstrua e publique:"
            aviso "  docker compose -f docker-compose-network-docker-internal.yml build ui"
            aviso "  docker push $(kubectl -n "$NS" get deploy ui \
                    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
            aviso "  kubectl -n $NS rollout restart deploy/ui"
        fi
    else
        aviso "nao descobri a URL de entrada -- a UI pode nao conseguir chamar as APIs."
        aviso "corrija com: kubectl -n $NS set env deploy/ui FIAP_API_BASE=http://IP:PORTA"
    fi
fi

# ---- conferencia do sidecar -------------------------------------------------
if [ "$COM_ISTIO" = 1 ]; then
    # ATENCAO: o istio-proxy pode estar em DOIS lugares. Desde o Istio 1.2x
    # com Kubernetes 1.29+, a injecao usa SIDECAR NATIVO: o Envoy entra como
    # initContainer com restartPolicy: Always, e NAO aparece em
    # .spec.containers. Olhar so' containers faz toda a malha parecer ausente
    # -- o pod esta 2/2, com Envoy, e o script acusa "sem sidecar".
    SEM_SIDECAR=$(kubectl -n "$NS" get pods \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.initContainers[*].name}{" "}{.spec.containers[*].name}{"\n"}{end}' \
        2>/dev/null | grep -v istio-proxy | grep -v '^mongodb' | wc -l | tr -d ' ')
    if [ "${SEM_SIDECAR:-0}" -gt 0 ]; then
        aviso "$SEM_SIDECAR pod(s) sem sidecar do Envoy -- sem ele nao ha malha:"
        aviso "nada de Kiali, fault injection, retry ou canary."
        aviso "confirme pela coluna READY (2/2 = com Envoy):"
        aviso "  kubectl -n $NS get pods"
        diagnosticar_sidecar
    fi
fi

mostrar_urls
# ---- proximos passos -------------------------------------------------------
# Comentado de proposito: o roteiro ja' esta no k8s/README.md e o bloco so'
# empurrava a URL do lab para fora da tela. Para voltar a imprimir, descomente.
# cat <<EOF
#   PROXIMOS PASSOS
#
#   1. A carga ja' esta rodando (deployment stress-carga, 3 replicas).
#      Confira que ela esta gerando trafego de verdade:
#
#        kubectl -n $NS logs -l app=stress-carga --tail=5
#        kubectl -n $NS get pods
#
#   2. Instale o Dynatrace:  cat k8s/dynatrace/README.md
#
#   3. DEIXE RODANDO 30-40 MINUTOS antes do game day. E' o tempo de que o
#      Davis precisa para saber como e' o normal deste sistema. Use esse
#      intervalo para os blocos 1 e 2 do roteiro (cluster e malha), que nao
#      dependem do Dynatrace.
#
#   4. So' entao:  bash k8s/caos.sh status
# EOF
