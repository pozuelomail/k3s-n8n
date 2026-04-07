#!/bin/bash
# ============================================
# Script para crear Secrets de Kubernetes desde ~/.env
# Uso: source ~/.env && ./create-secrets.sh [dev|pre|pro|all]
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar variables de entorno
if [ -f ~/.env ]; then
    set -a
    source ~/.env
    set +a
    echo "✓ Variables cargadas desde ~/.env"
else
    echo "Error: No se encuentra ~/.env"
    exit 1
fi

ENV=${1:-all}

create_secrets_for_env() {
    local env=$1
    local namespace="n8n-${env}"

    # Determinar variables según entorno
    case $env in
        dev)
            N8N_USER="${N8N_DEV_USERNAME}"
            N8N_PASS="${N8N_DEV_PASSWORD}"
            N8N_KEY="${N8N_DEV_ENCRYPTION_KEY}"
            PG_USER="${POSTGRES_DEV_USERNAME}"
            PG_PASS="${POSTGRES_DEV_PASSWORD}"
            PG_DB="${POSTGRES_DEV_DATABASE}"
            ;;
        pre)
            N8N_USER="${N8N_PRE_USERNAME}"
            N8N_PASS="${N8N_PRE_PASSWORD}"
            N8N_KEY="${N8N_PRE_ENCRYPTION_KEY}"
            PG_USER="${POSTGRES_PRE_USERNAME}"
            PG_PASS="${POSTGRES_PRE_PASSWORD}"
            PG_DB="${POSTGRES_PRE_DATABASE}"
            ;;
        pro)
            N8N_USER="${N8N_PRO_USERNAME}"
            N8N_PASS="${N8N_PRO_PASSWORD}"
            N8N_KEY="${N8N_PRO_ENCRYPTION_KEY}"
            PG_USER="${POSTGRES_PRO_USERNAME}"
            PG_PASS="${POSTGRES_PRO_PASSWORD}"
            PG_DB="${POSTGRES_PRO_DATABASE}"
            ;;
        *)
            echo "Entorno no válido: $env"
            return 1
            ;;
    esac

    echo ""
    echo "=========================================="
    echo "Creando Secrets para entorno: $env"
    echo "Namespace: $namespace"
    echo "=========================================="

    # Crear namespace si no existe
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

    # Crear Secret para n8n (auth)
    echo "Creando Secret n8n-${env}-auth..."
    kubectl create secret generic "n8n-${env}-auth" \
        --from-literal=username="${N8N_USER}" \
        --from-literal=password="${N8N_PASS}" \
        --from-literal=encryptionKey="${N8N_KEY}" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Crear Secret para PostgreSQL
    echo "Creando Secret ${env}-postgresql..."
    kubectl create secret generic "${env}-postgresql" \
        --from-literal=postgres-password="${PG_PASS}" \
        --from-literal=password="${PG_PASS}" \
        --from-literal=username="${PG_USER}" \
        --from-literal=dbname="${PG_DB}" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "✓ Secrets creados para $env"
    echo ""
    echo "Verificar:"
    echo "  kubectl get secrets -n $namespace"
}

case $ENV in
    dev|pre|pro)
        create_secrets_for_env "$ENV"
        ;;
    all)
        create_secrets_for_env "dev"
        create_secrets_for_env "pre"
        create_secrets_for_env "pro"
        ;;
    *)
        echo "Uso: $0 [dev|pre|pro|all]"
        echo ""
        echo "Ejemplos:"
        echo "  source ~/.env && $0 dev     # Solo desarrollo"
        echo "  source ~/.env && $0 all     # Todos los entornos"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Secrets creados exitosamente"
echo "=========================================="
echo ""
echo "Nota: Estos Secrets son referenciados por Helm"
echo "durante el despliegue. No se incluyen en Git."
