#!/usr/bin/env bash
# =============================================================================
# Publica as imagens do FIAP OTEL Bank no Docker Hub
# =============================================================================
#   bash publicar-imagens.sh              constroi e publica com :lab e :<sha>
#   bash publicar-imagens.sh --so-tag     so' reetiqueta e publica o que ja' existe
#   bash publicar-imagens.sh --dry-run    mostra o que faria, sem enviar nada
#
#   REGISTRO_IMAGENS=outro bash publicar-imagens.sh     outro usuario/organizacao
#   PLATAFORMAS=linux/arm64 bash publicar-imagens.sh    outra arquitetura
#
# POR QUE PUBLICAR
# Nao e' so' velocidade. O build leva 10-20 min E depende do PyPI e do npm
# estarem de pe' na hora da aula -- mesmo com todas as versoes fixas, um
# espelho fora do ar deixa o aluno sem ambiente. Uma imagem publicada e' um
# artefato fixo: o mesmo bit para todo mundo, sempre.
#
# DUAS TAGS, DE PROPOSITO
#   :lab      movel, e' a que os laboratorios usam por padrao
#   :<sha>    imutavel, o commit que gerou a imagem
# Sem a segunda, um dia a imagem publicada e o repositorio divergem em silencio
# e o aluno roda uma coisa enquanto o gabarito descreve outra.
#
# Rode `docker login` antes. Este script nao lida com credenciais.
# =============================================================================

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

REGISTRO="${REGISTRO_IMAGENS:-tonanuvem}"
TAG="${TAG_IMAGENS:-lab}"
PLATAFORMAS="${PLATAFORMAS:-linux/amd64}"

# A EC2 do laboratorio e' x86_64, por isso o padrao e' linux/amd64 -- e nao a
# arquitetura de quem publica. Num Mac ARM, `docker compose build` sem isto
# geraria imagens arm64 com o nome certo, e o aluno so' descobriria na aula,
# com "exec format error" depois do pull.
#
# Uma lista separada por virgula NAO cabe neste fluxo: o script constroi
# localmente e depois envia por tag, e o armazenamento local de imagens do
# Docker guarda uma arquitetura por tag. Manifesto multi-arquitetura exige
# `docker buildx bake --push`, que constroi e envia num passo so'.
case "$PLATAFORMAS" in
    *,*) echo "[ERRO] PLATAFORMAS aceita uma arquitetura por vez (recebido: $PLATAFORMAS)."
         echo "       Multi-arquitetura precisa de 'docker buildx bake --push'."
         exit 1 ;;
esac
ARQ_ESPERADA="${PLATAFORMAS##*/}"
COMPOSE="docker-compose-network-docker-internal.yml"

# nginx e locust ficam de fora: o nginx constroi em segundos, e a imagem do
# locust e' procurada pelo nome "fiap-bank-locust" no carga-locust.sh do
# repositorio do Splunk -- renomea-la quebraria aquele laboratorio.
SERVICOS="dashboard accounts transactions loan customer-auth atm-locator ui"

SO_TAG=false
DRY=false
for ARG in "$@"; do
    case "$ARG" in
        --so-tag)  SO_TAG=true ;;
        --dry-run) DRY=true ;;
        -h|--help) sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "[ERRO] opcao desconhecida: $ARG"; exit 1 ;;
    esac
done

ok()    { echo "  [OK] $1"; }
erro()  { echo "  [ERRO] $1"; }
aviso() { echo "  [!]  $1"; }

SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "sem-git")
SUJO=""
[ -n "$(git status --porcelain 2>/dev/null)" ] && SUJO="sim"

echo
echo "=================================================="
echo " PUBLICANDO AS IMAGENS DO FIAP OTEL BANK"
echo "=================================================="
echo
echo "  registro     $REGISTRO"
echo "  tags         :$TAG  e  :$SHA"
echo "  plataformas  $PLATAFORMAS"
echo "  imagens      $(echo $SERVICOS | wc -w | tr -d ' ')"
[ -n "$SUJO" ] && [ "$DRY" = "true" ] && echo "  ATENCAO      repositorio com mudancas nao commitadas"
echo

if [ -n "$SUJO" ] && [ "$DRY" != "true" ]; then
    aviso "o repositorio tem mudancas nao commitadas."
    echo "       A tag :$SHA vai apontar para um commit que NAO descreve o que"
    echo "       esta sendo publicado. Commite antes, ou a rastreabilidade se perde."
    echo
    printf "  Continuar assim? [s/N] "
    read -r R; case "$R" in s|S|sim|SIM) : ;; *) echo "  cancelado."; exit 0 ;; esac
fi

# `docker info` so' mostra "Username:" quando a credencial esta em texto no
# config.json. O Docker Desktop guarda num helper externo (credsStore), e ali
# o campo vem VAZIO mesmo autenticado -- o aviso disparava sempre, treinando
# quem publica a responder "s" no automatico e esvaziando a protecao.
usuario_docker() {
    local u store
    u=$(docker system info 2>/dev/null | sed -n 's/^ *Username: *//p')
    [ -n "$u" ] && { echo "$u"; return 0; }
    store=$(sed -n 's/.*"credsStore"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "${DOCKER_CONFIG:-$HOME/.docker}/config.json" 2>/dev/null)
    [ -z "$store" ] && return 1
    command -v "docker-credential-$store" >/dev/null 2>&1 || return 1
    "docker-credential-$store" list 2>/dev/null \
        | sed -n 's|.*"https://index.docker.io/v1/"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p'
}

USUARIO=$(usuario_docker)
if [ "$DRY" != "true" ] && [ -z "$USUARIO" ]; then
    aviso "voce nao parece estar autenticado no Docker Hub."
    echo "       Rode antes:  docker login"
    echo
    printf "  Tentar mesmo assim? [s/N] "
    read -r R; case "$R" in s|S|sim|SIM) : ;; *) echo "  cancelado."; exit 0 ;; esac
fi

# --------------------------------------------------------------- construir
if [ "$SO_TAG" != "true" ]; then
    echo "1. CONSTRUINDO"
    echo "--------------------------------------------------"
    if [ "$DRY" = "true" ]; then
        echo "  (dry-run) docker compose -f $COMPOSE build"
    else
        REGISTRO_IMAGENS="$REGISTRO" TAG_IMAGENS="$TAG" \
        DOCKER_DEFAULT_PLATFORM="$PLATAFORMAS" \
            docker compose -f "$COMPOSE" build $SERVICOS || { erro "build falhou"; exit 1; }
        ok "imagens construidas"
    fi
    echo
fi

# ------------------------------------------------------------------ enviar
echo "2. ENVIANDO"
echo "--------------------------------------------------"
FALHAS=0
for S in $SERVICOS; do
    ORIGEM="$REGISTRO/fiap-bank-${S}-otel:$TAG"
    DESTINO="$REGISTRO/fiap-bank-${S}-otel:$SHA"

    if [ "$DRY" = "true" ]; then
        echo "  (dry-run) push $ORIGEM  e  $DESTINO"
        continue
    fi

    if ! docker image inspect "$ORIGEM" >/dev/null 2>&1; then
        erro "$ORIGEM nao existe localmente -- construa antes (sem --so-tag)"
        FALHAS=$((FALHAS + 1)); continue
    fi

    # Conferir antes de enviar, e nao depois: uma imagem da arquitetura errada
    # sobe sem reclamar e so' falha na maquina do aluno.
    ARQ=$(docker image inspect "$ORIGEM" --format '{{.Architecture}}' 2>/dev/null)
    if [ "$ARQ" != "$ARQ_ESPERADA" ]; then
        erro "$S e' $ARQ, mas o esperado era $ARQ_ESPERADA -- reconstrua sem --so-tag"
        FALHAS=$((FALHAS + 1)); continue
    fi

    docker tag "$ORIGEM" "$DESTINO"
    if docker push -q "$ORIGEM" >/dev/null 2>&1 && docker push -q "$DESTINO" >/dev/null 2>&1; then
        ok "$S"
    else
        erro "falha ao enviar $S"
        FALHAS=$((FALHAS + 1))
    fi
done

echo
echo "=================================================="
if [ "$DRY" = "true" ]; then
    echo " DRY-RUN -- nada foi enviado"
elif [ "$FALHAS" -eq 0 ]; then
    echo " PUBLICADO"
    echo
    echo "  Os laboratorios ja' usam :$TAG por padrao -- nao e' preciso mudar nada."
    echo "  Para fixar esta versao num lab:  TAG_IMAGENS=$SHA bash run-lab.sh"
else
    echo " $FALHAS FALHA(S) -- veja acima"
fi
echo "=================================================="
echo
