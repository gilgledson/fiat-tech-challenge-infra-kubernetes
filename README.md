# oficina-infra-kubernetes

Infraestrutura como código (Terraform) do cluster Kubernetes (AKS) + API
Gateway (Traefik) + monitoramento de recursos do cluster (New Relic
Infrastructure, via Helm). Um dos 4 repositórios do Tech Challenge Fase 3 —
ver os outros:

- [oficina-app](https://github.com/SEU_USUARIO/oficina-app) — aplicação principal (roda neste cluster)
- [oficina-infra-banco-dados](https://github.com/SEU_USUARIO/oficina-infra-banco-dados) — Terraform do Postgres gerenciado
- [oficina-lambda-auth-cpf](https://github.com/SEU_USUARIO/oficina-lambda-auth-cpf) — Function Serverless de autenticação por CPF

> Atualize os links acima com as URLs reais assim que os repositórios forem
> criados no GitHub.

## Propósito

Este repositório é o **dono do Resource Group** Azure (`oficina-resources`)
e provisiona:

- O cluster **AKS** (`oficina-aks-cluster`) onde a aplicação principal roda.
- O **API Gateway** (Traefik), como Ingress Controller do cluster —
  `k8s/gateway/`.
- A integração de **monitoramento de infraestrutura** do New Relic
  (CPU/memória de nós e pods, eventos do cluster, forwarding de logs) via
  Helm chart — `k8s/observability/`.

Os outros 3 repositórios leem o Resource Group criado aqui via `data
source` (nunca o recriam) — este é o **primeiro repositório a ser
aplicado**.

## Arquitetura

```
Internet → Service traefik (LoadBalancer, :80) → Traefik (Ingress Controller)
         → Ingress oficina-api-ingress → Service oficina-api-service (ClusterIP)
         → Pods da aplicação (deployados pelo repositório oficina-app)
```

O `Ingress` em `k8s/gateway/ingress.yaml` assume que o repositório
`oficina-app` já aplicou `oficina-api-service` no namespace `default` —
ele só roteia para um Service que precisa existir, não o cria.

Ver o
[Diagrama de Componentes completo](https://github.com/SEU_USUARIO/oficina-app/blob/main/docs/architecture/diagrama-componentes.png)
no repositório `oficina-app` para a visão de todo o sistema.

## Tecnologias

- Terraform (`provider "azurerm"`) — AKS, Resource Group
- [Traefik](https://traefik.io/) — API Gateway / Ingress Controller
- Helm (`newrelic/nri-bundle`) — monitoramento de infraestrutura do cluster

## Como aplicar

### 1. Infraestrutura (Terraform)

```bash
cd infra
terraform init
terraform plan
terraform apply
```

Sem variáveis obrigatórias — este repositório não lida com segredos
diretamente (a senha do Postgres e as chaves ficam nos repositórios que
realmente as usam).

### 2. Configurar `kubectl`

```bash
az aks get-credentials --resource-group oficina-resources --name oficina-aks-cluster
```

### 3. API Gateway (Traefik)

```bash
kubectl apply -f k8s/gateway/namespace.yaml
kubectl apply -f k8s/gateway/rbac.yaml
kubectl apply -f k8s/gateway/ingressclass.yaml
kubectl apply -f k8s/gateway/deployment.yaml
kubectl apply -f k8s/gateway/service.yaml
# k8s/gateway/ingress.yaml só depois que o repositório oficina-app tiver
# aplicado o Service da aplicação:
kubectl apply -f k8s/gateway/ingress.yaml
```

### 4. Monitoramento de infraestrutura (Helm)

```bash
helm repo add newrelic https://helm-charts.newrelic.com
helm repo update
helm upgrade --install newrelic-bundle newrelic/nri-bundle \
  --namespace newrelic --create-namespace \
  --set global.licenseKey=<sua-license-key> \
  -f k8s/observability/newrelic-values.yaml
```

## Por que o `terraform apply` é manual (não roda em CI)

O `terraform plan` roda automaticamente em todo Pull Request (ver
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)) como verificação —
mas o `apply` é deliberadamente manual. Provisionar/alterar um cluster
Kubernetes e sua VM subjacente automaticamente a cada merge é um risco
desproporcional (custo, drift de credenciais — já vivenciado durante o
desenvolvimento deste projeto, ver ADRs no repositório `oficina-app`) para
um projeto deste porte. A aplicação (`oficina-app`) tem deploy 100%
automático porque é código-fonte com testes; infraestrutura de cluster é
tratada com uma etapa manual de revisão antes do `apply`, deliberadamente.

## Custos

Os recursos aqui (AKS + a VM do node pool) ficam **ligados 24/7** e cobram
por tempo, independente de uso. Rode `terraform destroy` quando não estiver
trabalhando ativamente no projeto, para evitar cobrança desnecessária.
