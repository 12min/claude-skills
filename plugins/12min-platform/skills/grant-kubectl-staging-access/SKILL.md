---
name: grant-kubectl-staging-access
description: >
  Concede a um dev acesso kubectl STAGING-ONLY ao cluster GKE api-staging-0
  (projeto min-b302a) para rodar o Maestro E2E anon-user com VERIFY_DB=1.
  Modelo least-privilege: IAM read-only (roles/container.clusterViewer) +
  RBAC namespaced (pods get/list + pods/exec create) aplicado SÓ no staging —
  produção (api-production) fica intocada. Inclui grant, verificação do limite,
  checklist do dev e revoke.
  Use when: usuário pede "dar acesso kubectl pro <dev>", "novo dev rodar
  VERIFY_DB", "acesso staging exec", "grant kubectl staging access",
  "kubectl staging E2E", ou onboarding de QA E2E que precise de exec no pod
  api-staging.

---

# Grant kubectl staging access (VERIFY_DB E2E)

Permite que um dev rode `scripts/maestro-local.sh` / `scripts/maestro-local-ios.sh`
(repo `12min/mobile-v2`) com `VERIFY_DB=1`, que executa:

```bash
kubectl --context gke_min-b302a_us-central1-c_api-staging-0 get pods            # acha pod api-staging
kubectl --context gke_min-b302a_us-central1-c_api-staging-0 exec <pod> -c api -- sh -c 'psql ...'
```

## Fatos do cluster

- **Projeto GCP:** `min-b302a`
- **Cluster staging:** `api-staging-0`, zona `us-central1-c`
- **Contexto kube:** `gke_min-b302a_us-central1-c_api-staging-0`
- **Namespace dos pods api-staging:** `default`
- **Produção (NÃO necessária):** `api-production`, zona `southamerica-east1-a`

## Modelo de acesso — staging-only (least privilege)

Duas camadas. A segunda é o que mantém staging-only:

1. **IAM (nível projeto, read-only):** `roles/container.clusterViewer`. Permite
   `get-credentials` + autenticar. Sozinho NÃO dá acesso a workload (não lista/exec pod).
2. **Kubernetes RBAC (cluster staging, ns `default`):** Role com `pods get/list` +
   `pods/exec create`, vinculada ao email do dev. RBAC é por-cluster → produção não
   tem binding → sem exec em prod. Manifesto bundled: `qa-verify-db-staging-rbac.yaml`.

> Residual aceito: `container.clusterViewer` é projeto-wide read-only → o dev consegue
> VER metadados do cluster de prod / fazer get-credentials dele, mas toda ação de
> workload em prod retorna Forbidden (sem RBAC lá). Capacidade real de exec = só staging.

## Pré-requisitos

- Quem roda precisa ser **owner** (ou ter `resourcemanager.projects.setIamPolicy` +
  admin do GKE) no `min-b302a`. Confirme: `gcloud config get-value account`.
- `kubectl` apontando pro contexto staging (este skill faz get-credentials se faltar).

## Passo 1 — DISCUTIR antes de executar (outward-facing: concede acesso a uma pessoa)

1. **Confirmar o email @12min.com exato do dev.** Convenção é mista (`andrew@`,
   `rafa@` mas também `renato.filho@`) — NÃO assuma; pergunte/valide. O grant usa
   o email verbatim.
2. **Confirmar o escopo.** Default = staging-only (este skill). Se pedirem amplo,
   `roles/container.developer` projeto-wide cobre exec em TODOS clusters (inclui prod) —
   só use se explicitamente quiserem.
3. Checar se já tem binding: `gcloud projects get-iam-policy min-b302a --flatten="bindings[].members" --filter="bindings.members:<dev>" --format="value(bindings.role)"`

## Passo 2 — IAM (read-only)

```bash
gcloud projects add-iam-policy-binding min-b302a \
  --member="user:<dev-email>" --role="roles/container.clusterViewer" --condition=None
```

## Passo 3 — RBAC (só staging)

Edite `qa-verify-db-staging-rbac.yaml` (deste dir): adicione o dev como `subject` no
RoleBinding (mantenha os existentes), depois aplique SÓ no contexto staging:

```bash
kubectl --context gke_min-b302a_us-central1-c_api-staging-0 \
  apply -f qa-verify-db-staging-rbac.yaml
```

## Passo 4 — Verificar o limite (impersonation, como owner)

```bash
S=gke_min-b302a_us-central1-c_api-staging-0
P=gke_min-b302a_southamerica-east1-a_api-production
kubectl --context $S auth can-i create pods --subresource=exec -n default --as=<dev-email>  # yes
kubectl --context $S auth can-i get pods -n default --as=<dev-email>                        # yes
kubectl --context $P auth can-i create pods --subresource=exec -n default --as=<dev-email>  # no
```

> **Gotcha:** use `create pods --subresource=exec` para o check. A forma com barra
> `auth can-i create pods/exec` constrói um SAR que NÃO casa com a regra RBAC e dá
> um "no" falso.

## Checklist do dev (na máquina dele)

```bash
# 1. Instalar gcloud + kubectl + plugin de auth do GKE (obrigatório p/ kubectl >=1.26)
brew install --cask google-cloud-sdk
gcloud components install kubectl gke-gcloud-auth-plugin

# 2. Login com a conta @12min.com
gcloud auth login

# 3. Pegar credenciais do staging e selecionar o contexto
gcloud container clusters get-credentials api-staging-0 --zone us-central1-c --project min-b302a
kubectl config use-context gke_min-b302a_us-central1-c_api-staging-0

# 4. Smoke test — deve listar pods api-staging Running
kubectl get pods | grep api-staging

# 5. Rodar o E2E com verificação de DB
VERIFY_DB=1 ./scripts/maestro-local.sh <flow>        # Android
VERIFY_DB=1 ./scripts/maestro-local-ios.sh <flow>    # iOS
```

Opcional: copiar os aliases `get-credentials-api-staging` + `kubectl-staging` do `~/.zshrc`.

## Revoke

```bash
# Tira só esse dev: remova o subject do RoleBinding e re-aplique. Ou dropa o binding inteiro:
kubectl --context gke_min-b302a_us-central1-c_api-staging-0 delete rolebinding qa-verify-db -n default
# Tira IAM:
gcloud projects remove-iam-policy-binding min-b302a \
  --member="user:<dev-email>" --role="roles/container.clusterViewer"
```

## Log de concessões

- **2026-06-09** — `ricardo@12min.com` — IAM `roles/container.clusterViewer` — RBAC `qa-verify-db` (staging/default)
