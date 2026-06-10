# k3s-n8n

Helm chart propio para desplegar n8n en k3s con nginx ingress, cert-manager y PostgreSQL.

## Stack

- k3s (Kubernetes ligero)
- Helm 3, chart custom en `helm/n8n/` con dependencia `bitnami/postgresql 15.x`
- n8n 1.x (`n8nio/n8n`)
- nginx ingress controller (NO traefik)
- cert-manager con ClusterIssuer `letsencrypt-prod`
- external-dns para `*.qforexwin.com`

## Entornos

| Entorno | Namespace | URL |
|---------|-----------|-----|
| dev | n8n-dev | https://n8n-dev.qforexwin.com |
| pre | n8n-pre | https://n8n-pre.qforexwin.com |
| pro | n8n-pro | https://n8n.qforexwin.com |

## Operaciones comunes

```bash
# 1. Crear secrets (solo la primera vez o al rotar credenciales)
source ~/.env && ./scripts/create-secrets.sh pro

# 2. Desplegar
./scripts/deploy.sh pro

# 3. Verificar estado
kubectl get pods,svc,ingress,certificate,networkpolicy -n n8n-pro

# 4. Logs
kubectl logs -f -n n8n-pro -l app.kubernetes.io/name=n8n

# 5. Backup
./scripts/backup.sh pro
```

## Variables requeridas en ~/.env

```bash
N8N_PRO_ENCRYPTION_KEY=<32+ chars aleatorios>
POSTGRES_PRO_USERNAME=n8n_pro
POSTGRES_PRO_PASSWORD=<password seguro>
POSTGRES_PRO_DATABASE=n8n_pro

# Dev y pre siguen el mismo patron con sufijo DEV/PRE
```

## Estructura del chart

```
helm/n8n/
  Chart.yaml                  # version 2.0.0, appVersion 1.91.3
  values.yaml                 # Valores base (className: nginx)
  values-dev.yaml
  values-pre.yaml
  values-pro.yaml
  templates/
    _helpers.tpl              # fullname, labels, serviceAccountName, authSecretName
    namespace.yaml
    serviceaccount.yaml       # automountServiceAccountToken: false
    deployment.yaml           # securityContext, emptyDir /tmp, strategy: Recreate
    service.yaml
    ingress.yaml              # nginx-only, cert-manager annotation
    pvc.yaml
    secrets.yaml              # Solo si no hay existingAuthSecret
    networkpolicy.yaml        # default-deny + allow ingress-nginx + postgres interno
    hpa.yaml                  # Deshabilitado por defecto
```

## Reglas de seguridad

- `image.tag` siempre fijado — nunca `latest` en pro
- `strategy.type: Recreate` — PVC es ReadWriteOnce, rolling update no funciona
- `replicaCount: 1` en modo `regular` — para 2+ replicas hace falta queue mode con Redis
- `readOnlyRootFilesystem: true` — n8n escribe en `/home/node/.n8n` (PVC) y `/tmp` (emptyDir)
- NetworkPolicy habilitada — default-deny, solo ingress desde ingress-nginx y egress a postgres + DNS + HTTPS
- Secrets siempre externos (`existingAuthSecret`, `postgresql.auth.existingSecret`) — nunca en values
- Ingress siempre `className: nginx` — el ClusterIssuer usa `ingressClassName: nginx` para el solver ACME

## Dependencias Helm

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm dependency update helm/n8n/
```

## Troubleshooting

**Pod en Pending tras upgrade**: Con `strategy: Recreate` el pod viejo termina antes de que arranque el nuevo. Si queda en Pending, verificar que el PVC fue liberado: `kubectl get pvc -n n8n-pro`.

**Certificado no se emite**: Verificar que el ClusterIssuer `letsencrypt-prod` tiene `ingressClassName: nginx` (no `class: traefik`): `kubectl describe clusterissuer letsencrypt-prod`.

**Error de permisos en filesystem**: Si n8n falla con errores de escritura, verificar que el emptyDir de `/tmp` está montado: `kubectl describe pod -n n8n-pro`.

**PostgreSQL password error**: El secret `{env}-postgresql` debe tener las keys `password` (usuario n8n) y `postgres-password` (admin). El subchart Bitnami 15.x usa exactamente esas keys.

**n8n pide crear cuenta owner en primer acceso**: Normal en n8n 1.x. La autenticación básica fue eliminada — se crea un usuario administrador en el primer acceso a la UI.
