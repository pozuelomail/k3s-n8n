#!/bin/bash
# ============================================
# Script de despliegue de n8n
# Uso: ./deploy.sh [dev|pre|pro]
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

ENV=${1:-dev}

case $ENV in
    dev|pre|pro)
        echo "Desplegando en entorno: $ENV"
        ;;
    *)
        echo "Error: Entorno no valido. Usar: dev, pre o pro"
        echo "Uso: ./deploy.sh [dev|pre|pro]"
        exit 1
        ;;
esac

echo "=========================================="
echo "Despliegue de n8n - Entorno: $ENV"
echo "=========================================="

CHART_DIR="${REPO_ROOT}/helm/n8n"
VALUES_FILE="${CHART_DIR}/values-${ENV}.yaml"
RELEASE_NAME="n8n-${ENV}"
NAMESPACE="n8n-${ENV}"

if [[ ! -f "$VALUES_FILE" ]]; then
    echo "Error: No se encuentra $VALUES_FILE"
    exit 1
fi

if [[ "$ENV" == "pro" ]]; then
    echo ""
    echo "ADVERTENCIA: Estas desplegando en PRODUCCION"
    read -p "Escribe 'SI' para confirmar: " confirm
    if [[ "$confirm" != "SI" ]]; then
        echo "Despliegue cancelado"
        exit 0
    fi
fi

echo ""
echo "Verificando Secrets requeridos..."
SECRETS_OK=true
for secret in "n8n-${ENV}-auth" "${ENV}-postgresql"; do
    if ! kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
        echo "ERROR: Secret '$secret' no encontrado en namespace '$NAMESPACE'"
        echo "Ejecutar: source ~/.env && ./scripts/create-secrets.sh $ENV"
        SECRETS_OK=false
    fi
done
if [[ "$SECRETS_OK" == "false" ]]; then
    exit 1
fi
echo "OK — Secrets verificados"

echo ""
echo "Actualizando repositorios y dependencias de Helm..."
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true
helm repo update
helm dependency update "$CHART_DIR"

echo ""
echo "Desplegando con Helm..."
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
    -f "${CHART_DIR}/values.yaml" \
    -f "$VALUES_FILE" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait \
    --atomic \
    --timeout 10m

echo ""
echo "=========================================="
echo "Despliegue completado: $ENV"
echo "=========================================="
echo ""
echo "Estado:"
echo "  kubectl get pods,svc,ingress,certificate,networkpolicy -n $NAMESPACE"
echo ""
echo "Logs:"
echo "  kubectl logs -f -n $NAMESPACE -l app.kubernetes.io/name=n8n"
echo ""
HOST=$(grep 'host:' "$VALUES_FILE" | head -1 | awk '{print $2}')
echo "URL: https://${HOST}"
