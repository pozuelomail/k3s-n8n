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
echo "Verificando ClusterIssuer..."
echo "=========================================="

# Verificar si el ClusterIssuer ya existe
if kubectl get clusterissuer letsencrypt-prod &>/dev/null; then
    echo "✓ ClusterIssuer letsencrypt-prod ya configurado"
    kubectl get clusterissuer
    echo ""
    echo "Usando ClusterIssuer existente..."
else
    echo "Aplicando ClusterIssuer..."
    kubectl apply -f "${REPO_ROOT}/manifests/cert-manager/"
    echo ""
    echo "ClusterIssuer configurado:"
    kubectl get clusterissuer
fi

echo ""
echo "=========================================="
echo "cert-manager configurado correctamente"
echo "=========================================="
echo ""
echo "IMPORTANTE: Actualizar el email en el ClusterIssuer"
echo "antes de usar Let's Encrypt en producción:"
echo "  kubectl edit clusterissuer letsencrypt-prod"
