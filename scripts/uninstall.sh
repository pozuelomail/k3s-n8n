#!/bin/bash
# ============================================
# Script de desinstalación de n8n
# Uso: ./uninstall.sh [dev|pre|pro]
# ============================================
set -e

ENV=${1:-dev}
NAMESPACE="n8n-${ENV}"
RELEASE_NAME="n8n-${ENV}"

echo "=========================================="
echo "Desinstalación de n8n - Entorno: $ENV"
echo "=========================================="

if [[ "$ENV" == "pro" ]]; then
    echo "⚠️  ADVERTENCIA CRÍTICA: Estás eliminando el entorno de PRODUCCIÓN"
    echo "Se perderán todos los datos si no hay backup"
    echo ""
    read -p "¿Estás seguro? Escribe 'ELIMINAR_PRODUCCION' para confirmar: " confirm
    if [[ "$confirm" != "ELIMINAR_PRODUCCION" ]]; then
        echo "Desinstalación cancelada"
        exit 0
    fi
else
    read -p "¿Eliminar entorno $ENV? (s/N): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        echo "Desinstalación cancelada"
        exit 0
    fi
fi

echo ""
echo "Desinstalando release de Helm..."
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait || echo "Release no encontrado"

echo ""
echo "Eliminando namespace..."
kubectl delete namespace "$NAMESPACE" --wait=true --timeout=60s || echo "Namespace no encontrado"

echo ""
echo "=========================================="
echo "Desinstalación completada"
echo "=========================================="
echo ""
echo "Nota: Los PVCs (volúmenes persistentes) pueden requerir eliminación manual:"
echo "  kubectl get pvc -n $NAMESPACE"
echo "  kubectl delete pvc -n $NAMESPACE --all"
