#!/bin/bash
# ============================================
# Script de instalación de cert-manager
# ============================================
# NOTA: Este script detecta si cert-manager ya está instalado
# y solo aplica los ClusterIssuers si es necesario.
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

NAMESPACE="cert-manager"

echo "=========================================="
echo "Verificando cert-manager..."
echo "=========================================="

# Detectar si cert-manager ya está instalado
if kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=cert-manager &>/dev/null; then
    echo ""
    echo "✓ cert-manager ya está instalado en el cluster"
    kubectl get pods -n ${NAMESPACE}
    echo ""
    echo "Saltando instalación de cert-manager..."
else
    echo "Instalando cert-manager..."

    # Añadir repositorio de Jetstack
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update

    # Instalar cert-manager con CRDs
    helm upgrade --install cert-manager jetstack/cert-manager \
      --namespace ${NAMESPACE} \
      --create-namespace \
      --version v1.14.0 \
      --set installCRDs=true \
      --set prometheus.enabled=false

    echo "Esperando a que cert-manager esté listo..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n ${NAMESPACE} --timeout=120s
fi

echo ""
echo "=========================================="
echo "Verificando ClusterIssuers..."
echo "=========================================="

# Verificar si los ClusterIssuers ya existen
if kubectl get clusterissuer letsencrypt-prod &>/dev/null && kubectl get clusterissuer letsencrypt-staging &>/dev/null; then
    echo "✓ ClusterIssuers ya configurados:"
    kubectl get clusterissuer
    echo ""
    echo "Usando ClusterIssuers existentes..."
else
    echo "Aplicando ClusterIssuers..."
    kubectl apply -f "${REPO_ROOT}/manifests/cert-manager/"
    echo ""
    echo "ClusterIssuers configurados:"
    kubectl get clusterissuer
fi

echo ""
echo "=========================================="
echo "cert-manager configurado correctamente"
echo "=========================================="
echo ""
echo "IMPORTANTE: Actualizar el email en los ClusterIssuers"
echo "antes de usar Let's Encrypt en producción:"
echo "  kubectl edit clusterissuer letsencrypt-prod"
echo "  kubectl edit clusterissuer letsencrypt-staging"
