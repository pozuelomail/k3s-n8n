#!/bin/bash
# ============================================
# Script de backup de n8n
# Backup de volúmenes y base de datos PostgreSQL
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/../backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

ENV=${1:-pro}
NAMESPACE="n8n-${ENV}"
BACKUP_PATH="${BACKUP_DIR}/${ENV}/${TIMESTAMP}"

# Crear directorios
mkdir -p "$BACKUP_PATH"

echo "=========================================="
echo "Backup de n8n - Entorno: $ENV"
echo "Fecha: $(date)"
echo "=========================================="

# Backup de PostgreSQL
echo ""
echo "Realizando backup de PostgreSQL..."
POSTGRES_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$POSTGRES_POD" ]]; then
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- \
        pg_dumpall -U postgres > "${BACKUP_PATH}/postgres_all.sql"
    echo "✓ Backup PostgreSQL completado: ${BACKUP_PATH}/postgres_all.sql"
else
    echo "⚠ No se encontró pod de PostgreSQL"
fi

# Backup de volúmenes n8n
echo ""
echo "Realizando backup de volúmenes n8n..."
N8N_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=n8n -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$N8N_POD" ]]; then
    kubectl exec -n "$NAMESPACE" "$N8N_POD" -- \
        tar czf - /home/node/.n8n > "${BACKUP_PATH}/n8n_data.tar.gz" 2>/dev/null || echo "⚠ No se pudo hacer backup de datos n8n"
    echo "✓ Backup n8n completado: ${BACKUP_PATH}/n8n_data.tar.gz"
else
    echo "⚠ No se encontró pod de n8n"
fi

# Backup de recursos de Kubernetes
echo ""
echo "Exportando recursos de Kubernetes..."
kubectl get all -n "$NAMESPACE" -o yaml > "${BACKUP_PATH}/k8s_resources.yaml" 2>/dev/null || true
kubectl get secrets -n "$NAMESPACE" -o yaml > "${BACKUP_PATH}/k8s_secrets.yaml" 2>/dev/null || true
kubectl get configmaps -n "$NAMESPACE" -o yaml > "${BACKUP_PATH}/k8s_configmaps.yaml" 2>/dev/null || true

echo "✓ Backup de recursos Kubernetes completado"

# Crear resumen
echo ""
echo "=========================================="
echo "Backup completado: ${BACKUP_PATH}"
echo "=========================================="
ls -lah "$BACKUP_PATH"

# Limpiar backups antiguos (mantener últimos 10)
echo ""
echo "Limpiando backups antiguos..."
cd "${BACKUP_DIR}/${ENV}"
ls -t | tail -n +11 | xargs -r rm -rf
echo "✓ Limpieza completada (mantenidos últimos 10 backups)"
