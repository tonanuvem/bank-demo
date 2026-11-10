# Instalar o Dynatrace no cluster do LAB

> **Os tokens não entram neste repositório, nem no `.docx`.**
> Os dois rascunhos do LAB 3 têm tokens reais colados (`dt0c01.PHR7NN3R…` e
> `dt0c01.767GNYCD…`) e o id do tenant. Revogue os dois antes de distribuir
> qualquer versão do material: quem tem o *Operator token* opera o agente no
> cluster, e quem tem o *Data ingest* escreve no tenant.

## 0. Dois caminhos de instalação — e qual usar na aula

| Caminho | Custo | O que entrega |
|---|---|---|
| **Auto Discovery** (`dtwiz`, 4 linhas) | uma colagem | cluster monitorado, logs, code module em Python/Node, coletor OTLP |
| Assistente *Add cluster* com Full-Stack | ~10 passos, 2 tokens novos, download de YAML | o mesmo, mais a camada de host e processo |
| `dynakube.yaml` deste repo | tokens à mão | declarativo, versionado, conflita com os DynaKube do assistente |

Com 25 alunos ao mesmo tempo, o **Auto Discovery** ganha: é uma colagem só, e
as duas variáveis que ele exporta (`DT_ENVIRONMENT`, `DT_PLATFORM_TOKEN`)
servem para o resto da configuração. Full-stack não precisa ser decidido na
instalação: vira um `kubectl patch` depois.

Mas o Auto Discovery para antes de três coisas, e as três só aparecem quando
você procura o dado e ele não está lá. Depois dele, nesta ordem:

```
curl -s https://raw.githubusercontent.com/tonanuvem/k8s-exemplos/refs/heads/master/dynatrace-config.sh | bash
bash k8s/dynatrace/completar-autodiscovery.sh
```

O primeiro ajusta AppArmor e ActiveGate no DynaKube principal. O segundo
diagnostica o resto — token de ingestão sem escopo OTLP, injeção que não é
retroativa, e a escolha de full-stack — e **por padrão não muda nada**: cada
correção exige uma flag. Ver o cabeçalho do script.

---

## 1. Conta

`https://www.dynatrace.com/signup/` — trial de 15 dias.

Crie **perto da aula**, não com semanas de antecedência: o contador começa na
ativação e não no primeiro uso.

## 2. Service user e tokens

Em *Account Management → Identity & access management → Service users*, crie um
service user com as políticas **Kubernetes Operator** e **Kubernetes Ingest**.

Depois, em `https://myaccount.dynatrace.com/platformTokens`, gere **dois**
platform tokens associados a esse service user:

| Token | Para quê |
|---|---|
| Operator token | ciclo de vida dos componentes Dynatrace no cluster |
| Data ingest token | ingestão de métricas, logs e traces |

Cada token aparece **uma única vez**. Guarde na hora.

## 3. Operator

```bash
helm install dynatrace-operator \
  oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --create-namespace --namespace dynatrace --atomic
```

`--atomic` faz o helm desfazer sozinho se a instalação falhar no meio — sem
ele, o namespace fica num estado parcial que confunde o diagnóstico seguinte.

## 4. Secret com os tokens

```bash
read -rsp "Operator token: "    API_TOKEN;  echo
read -rsp "Data ingest token: " DATA_TOKEN; echo

kubectl -n dynatrace create secret generic dynakube \
  --from-literal="apiToken=$API_TOKEN" \
  --from-literal="dataIngestToken=$DATA_TOKEN"

unset API_TOKEN DATA_TOKEN
```

`read -rsp` em vez de colar o token na linha de comando: assim ele não fica no
`~/.bash_history` nem na tela projetada.

## 5. DynaKube

```bash
sed -i "s/SEU-AMBIENTE/mte16556/" k8s/dynatrace/dynakube.yaml   # id do seu tenant
kubectl apply -f k8s/dynatrace/dynakube.yaml
kubectl -n dynatrace get pods -w
```

## 6. Conferir

```bash
# os tokens foram aceitos?
kubectl -n dynatrace get dynakube dynakube \
  -o jsonpath='{.status.conditions}' | python3 -m json.tool

# o Istio liberou a saída do agente para o tenant?
kubectl -n dynatrace get serviceentry,virtualservice
```

Se as condições demorarem, force a reconciliação:

```bash
kubectl -n dynatrace annotate dynakube dynakube reconcile=$(date +%s) --overwrite
```

## Problemas conhecidos

| Sintoma | Causa |
|---|---|
| `no matches for kind "DynaKube"` | `apiVersion` errada — confira com `kubectl api-resources \| grep -i dynakube` |
| Agente instala e nada chega | `enableIstio: true` faltando, com mTLS STRICT |
| Pods do `dynatrace` em CrashLoop | geralmente falta de memória no nó — veja `kubectl -n dynatrace describe pod` |
| Cluster não aparece no app Kubernetes | capability `kubernetes-monitoring` ausente no ActiveGate |

## Desinstalar

```bash
kubectl delete -f k8s/dynatrace/dynakube.yaml
helm uninstall dynatrace-operator -n dynatrace
kubectl delete namespace dynatrace
```
