#!/usr/bin/env bash
#
# Cadastra no GitHub os secrets de deploy dos três microsserviços.
#
# Os valores nunca são mostrados na tela nem gravados em arquivo: o script lê
# o que já existe no cluster, cria a credencial de serviço na Azure, pergunta
# o que só você sabe, e manda tudo direto para o GitHub.
#
# Antes de rodar:
#   az login
#   gh auth login
#   az aks get-credentials --resource-group oficina-resources --name oficina-aks-cluster
#
# Uso:
#   ./scripts/cadastrar-secrets.sh             cadastra os secrets
#   ./scripts/cadastrar-secrets.sh --simular   só mostra o que seria cadastrado
#
set -euo pipefail

DONO="gilgledson"
REPO_OS="$DONO/fiat-tech-challenge-ddd"
REPO_BILLING="$DONO/oficina-billing-service"
REPO_EXECUTION="$DONO/oficina-execution-service"

GRUPO="oficina-resources"
NAMESPACE="default"
SECRET_OS="oficina-db-app"            # Secret do OS Service, criado na Fase 3
SECRET_RABBIT="rabbitmq-credentials"
SECRET_MONGO="mongodb-credentials"
NOME_SP="oficina-github-actions"      # credencial de serviço usada pelos pipelines

SIMULAR=false
[[ "${1:-}" == "--simular" ]] && SIMULAR=true

# ---------- apoio ----------

erro() { echo "ERRO: $*" >&2; exit 1; }

# Lê uma chave de um Secret do Kubernetes. Sai vazio se não existir.
do_cluster() {
  local secret="$1" chave="$2"
  kubectl get secret "$secret" -n "$NAMESPACE" -o "jsonpath={.data.$chave}" 2>/dev/null | base64 --decode 2>/dev/null || true
}

# Grava um secret em um repositório. O valor vai pela entrada padrão, para não
# aparecer na lista de processos nem no histórico do terminal.
gravar() {
  local repo="$1" nome="$2" valor="$3"
  if [[ -z "$valor" ]]; then
    echo "  - $nome: sem valor, não cadastrado"
    return
  fi
  if $SIMULAR; then
    echo "  - $nome: seria cadastrado (${#valor} caracteres)"
  else
    printf '%s' "$valor" | gh secret set "$nome" --repo "$repo" >/dev/null
    echo "  - $nome: cadastrado"
  fi
}

# Pergunta um valor sem mostrá-lo na tela. Enter vazio pula.
perguntar() {
  local rotulo="$1" valor
  read -r -s -p "$rotulo (Enter para pular): " valor
  echo >&2
  printf '%s' "$valor"
}

# ---------- pré-requisitos ----------

command -v gh >/dev/null || erro "instale a CLI do GitHub (gh)."
command -v az >/dev/null || erro "instale a CLI da Azure (az)."
command -v kubectl >/dev/null || erro "instale o kubectl."
gh auth status >/dev/null 2>&1 || erro "rode 'gh auth login' antes."
az account show >/dev/null 2>&1 || erro "rode 'az login' antes."
kubectl get secret "$SECRET_RABBIT" -n "$NAMESPACE" >/dev/null 2>&1 \
  || erro "não achei o Secret $SECRET_RABBIT no cluster. O kubectl está apontando para o cluster certo?"

$SIMULAR && echo "Modo de simulação: nada será gravado no GitHub nem criado na Azure."
echo

# ---------- valores que já existem no cluster ----------

RABBIT_USUARIO="$(do_cluster "$SECRET_RABBIT" username)"
RABBIT_SENHA="$(do_cluster "$SECRET_RABBIT" password)"
MONGO_USUARIO="$(do_cluster "$SECRET_MONGO" username)"
MONGO_SENHA="$(do_cluster "$SECRET_MONGO" password)"
MONGO_URL=""
if [[ -n "$MONGO_USUARIO" && -n "$MONGO_SENHA" ]]; then
  MONGO_URL="mongodb://${MONGO_USUARIO}:${MONGO_SENHA}@mongodb.${NAMESPACE}.svc.cluster.local:27017/?authSource=admin"
fi

# O Secret do OS Service guarda o usuário e a senha do Postgres, a license key
# do New Relic e a connection string do storage das assinaturas.
BANCO_USUARIO="$(do_cluster "$SECRET_OS" username)"
BANCO_SENHA="$(do_cluster "$SECRET_OS" password)"
NEW_RELIC="$(do_cluster "$SECRET_OS" new-relic-license-key)"
STORAGE="$(do_cluster "$SECRET_OS" azure-storage-connection-string)"

# ---------- credencial de serviço na Azure ----------

AZURE_CREDENTIALS=""
if $SIMULAR; then
  echo "Azure: seria criada a credencial de serviço '$NOME_SP', com acesso só ao grupo $GRUPO."
else
  echo "Os pipelines do Billing e do Execution precisam de uma credencial de serviço na Azure."
  echo "Vou criar '$NOME_SP', com papel Contributor restrito ao grupo $GRUPO."
  read -r -p "Criar agora? [s/N] " resposta
  if [[ "$resposta" =~ ^[sS]$ ]]; then
    ASSINATURA="$(az account show --query id -o tsv)"
    SAIDA="$(az ad sp create-for-rbac --name "$NOME_SP" --role Contributor \
      --scopes "/subscriptions/$ASSINATURA/resourceGroups/$GRUPO" -o json 2>/dev/null)" \
      || erro "não consegui criar a credencial de serviço na Azure."
    # Monta o JSON no formato que a action azure/login espera.
    AZURE_CREDENTIALS="$(SAIDA="$SAIDA" ASSINATURA="$ASSINATURA" python3 -c '
import json, os
s = json.loads(os.environ["SAIDA"])
print(json.dumps({
    "clientId": s["appId"],
    "clientSecret": s["password"],
    "subscriptionId": os.environ["ASSINATURA"],
    "tenantId": s["tenant"],
}))')"
    unset SAIDA
    echo "Credencial de serviço criada."
  else
    echo "Pulando: AZURE_CREDENTIALS não será cadastrado no Billing nem no Execution."
  fi
fi
echo

# ---------- valores que só você sabe ----------

DOCKER_USUARIO=""
DOCKER_TOKEN=""
MP_TOKEN=""
MP_SEGREDO=""
if ! $SIMULAR; then
  echo "Docker Hub (para o Billing e o Execution publicarem a imagem):"
  read -r -p "Usuário do Docker Hub (Enter para pular): " DOCKER_USUARIO
  DOCKER_TOKEN="$(perguntar "Access token do Docker Hub")"
  echo
  echo "Mercado Pago (opcional; sem eles o pagamento segue manual):"
  MP_TOKEN="$(perguntar "Access Token de teste (APP_USR-...)")"
  MP_SEGREDO="$(perguntar "Chave secreta do webhook")"
  echo
fi

# ---------- cadastro ----------

echo "OS Service ($REPO_OS):"
gravar "$REPO_OS" RABBITMQ_USERNAME "$RABBIT_USUARIO"
gravar "$REPO_OS" RABBITMQ_PASSWORD "$RABBIT_SENHA"
gravar "$REPO_OS" DB_APP_USERNAME "$BANCO_USUARIO"
echo

echo "Billing Service ($REPO_BILLING):"
gravar "$REPO_BILLING" AZURE_CREDENTIALS "$AZURE_CREDENTIALS"
gravar "$REPO_BILLING" DOCKERHUB_USERNAME "$DOCKER_USUARIO"
gravar "$REPO_BILLING" DOCKERHUB_TOKEN "$DOCKER_TOKEN"
gravar "$REPO_BILLING" BILLING_DB_PASSWORD "$BANCO_SENHA"
gravar "$REPO_BILLING" RABBITMQ_USERNAME "$RABBIT_USUARIO"
gravar "$REPO_BILLING" RABBITMQ_PASSWORD "$RABBIT_SENHA"
gravar "$REPO_BILLING" AZURE_STORAGE_CONNECTION_STRING "$STORAGE"
gravar "$REPO_BILLING" NEW_RELIC_LICENSE_KEY "$NEW_RELIC"
gravar "$REPO_BILLING" MERCADOPAGO_ACCESS_TOKEN "$MP_TOKEN"
gravar "$REPO_BILLING" MERCADOPAGO_WEBHOOK_SECRET "$MP_SEGREDO"
echo

echo "Execution Service ($REPO_EXECUTION):"
gravar "$REPO_EXECUTION" AZURE_CREDENTIALS "$AZURE_CREDENTIALS"
gravar "$REPO_EXECUTION" DOCKERHUB_USERNAME "$DOCKER_USUARIO"
gravar "$REPO_EXECUTION" DOCKERHUB_TOKEN "$DOCKER_TOKEN"
gravar "$REPO_EXECUTION" EXECUTION_MONGODB_URL "$MONGO_URL"
gravar "$REPO_EXECUTION" RABBITMQ_USERNAME "$RABBIT_USUARIO"
gravar "$REPO_EXECUTION" RABBITMQ_PASSWORD "$RABBIT_SENHA"
gravar "$REPO_EXECUTION" NEW_RELIC_LICENSE_KEY "$NEW_RELIC"
echo

if $SIMULAR; then
  echo "Simulação concluída. Rode sem --simular para cadastrar."
else
  echo "Pronto. Reexecute o pipeline da main de cada serviço para fazer o deploy."
fi
