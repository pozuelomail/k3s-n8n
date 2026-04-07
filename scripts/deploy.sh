#!/bin/bash
# ============================================
# Script de despliegue de n8n
# Uso: ./deploy.sh [dev|pre|pro]
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

ENV=${1:-dev}

# Validar entorno
case $ENV in
    dev|pre|pro)
        echo "Desplegando en entorno: $ENV"
        ;;
    *)
        echo "Error: Entorno no válido. Usar: dev, pre o pro"
        echo "Uso: ./deploy.sh [dev|pre|pro]"
        exit 1
        ;;
esac

echo "=========================================="
echo "Despliegue de n8n - Entorno: $ENV"
echo "=========================================="

# Añadir repositorios de Helm
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true
helm repo update

# Variables
CHART_DIR="${REPO_ROOT}/helm/n8n"
VALUES_FILE="${CHART_DIR}/values-${ENV}.yaml"
RELEASE_NAME="n8n-${ENV}"
NAMESPACE="n8n-${ENV}"

# Verificar que existen los archivos necesarios
if [[ ! -f "$VALUES_FILE" ]]; then
    echo "Error: No se encuentra $VALUES_FILE"
    exit 1
fi

echo ""
echo "Advertencia: Este script desplegará n8n en el entorno $ENV"
echo "Namespace: $NAMESPACE"
echo ""

if [[ "$ENV" == "pro" ]]; then
    echo "⚠️  ADVERTENCIA: Estás desplegando en PRODUCCIÓN"
    read -p "¿Estás seguro? (escribe 'SI' para confirmar): " confirm
    if [[ "$confirm" != "SI" ]]; then
        echo "Despliegue cancelado"
        exit 0
    fi
fi

echo ""
echo "=========================================="
echo "Actualizando dependencias de Helm..."
echo "=========================================="
helm dependency update "$CHART_DIR"

echo ""
echo "=========================================="
echo "Desplegando con Helm..."
echo "=========================================="
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
    -f "$VALUES_FILE" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait \
    --timeout 10m

echo ""
echo "=========================================="
echo "Despliegue completado en entorno: $ENV"
echo "=========================================="
echo ""
echo "Verificar estado:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl get svc -n $NAMESPACE"
echo "  kubectl get ingress -n $NAMESPACE"
echo ""
echo "Ver logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=n8n --tail=100"
echo ""
echo "Acceder a n8n:"
echo "  https://$(grep 'host:' $VALUES_FILE | head -1 | awk '{print $2}')"
