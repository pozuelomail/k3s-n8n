#!/bin/bash
# ============================================
# Script para crear Secrets de Kubernetes desde ~/.env
# Uso: source ~/.env && ./create-secrets.sh [dev|pre|pro|all]
#
# Variables requeridas en ~/.env por entorno:
#   N8N_{ENV}_ENCRYPTION_KEY
#   POSTGRES_{ENV}_USERNAME
#   POSTGRES_{ENV}_PASSWORD
#   POSTGRES_{ENV}_DATABASE
# ============================================
set -euo pipefail

if [ -f ~/.env ]; then
    set -a
    source ~/.env
    set +a
    echo "Variables cargadas desde ~/.env"
else
    echo "Error: No se encuentra ~/.env"
    exit 1
fi

ENV=${1:-all}

create_secrets_for_env() {
    local env=$1
    local namespace="n8n-${env}"
    local ENV_UPPER
    ENV_UPPER=$(echo "$env" | tr '[:lower:]' '[:upper:]')

    local key_var="N8N_${ENV_UPPER}_ENCRYPTION_KEY"
    local pg_user_var="POSTGRES_${ENV_UPPER}_USERNAME"
    local pg_pass_var="POSTGRES_${ENV_UPPER}_PASSWORD"
    local pg_db_var="POSTGRES_${ENV_UPPER}_DATABASE"

    local N8N_KEY="${!key_var:-}"
    local PG_USER="${!pg_user_var:-}"
    local PG_PASS="${!pg_pass_var:-}"
    local PG_DB="${!pg_db_var:-}"

    if [[ -z "$N8N_KEY" || -z "$PG_PASS" ]]; then
        echo "Error: Variables de entorno incompletas para '$env'"
        echo "Requeridas: $key_var, $pg_pass_var"
        return 1
    fi

    echo ""
    echo "=========================================="
    echo "Creando Secrets para entorno: $env"
    echo "Namespace: $namespace"
    echo "=========================================="

    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

    echo "Creando Secret n8n-${env}-auth..."
    kubectl create secret generic "n8n-${env}-auth" \
        --from-literal=encryptionKey="${N8N_KEY}" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "Creando Secret ${env}-postgresql..."
    kubectl create secret generic "${env}-postgresql" \
        --from-literal=postgres-password="${PG_PASS}" \
        --from-literal=password="${PG_PASS}" \
        --from-literal=username="${PG_USER}" \
        --from-literal=dbname="${PG_DB}" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "OK — Secrets creados para $env"
}

create_social_secrets_for_env() {
    local env=$1
    local namespace="n8n-${env}"
    local ENV_UPPER
    ENV_UPPER=$(echo "$env" | tr '[:lower:]' '[:upper:]')

    local anthropic_key="${ANTHROPIC_API_KEY:-}"
    local unsplash_key="${UNSPLASH_ACCESS_KEY:-}"
    local meta_page_id="${META_PAGE_ID:-}"
    local meta_ig_id="${META_IG_ACCOUNT_ID:-}"
    local meta_token="${META_PAGE_ACCESS_TOKEN:-}"

    if [[ -z "$anthropic_key" || -z "$unsplash_key" || -z "$meta_page_id" || -z "$meta_ig_id" || -z "$meta_token" ]]; then
        echo "AVISO: Faltan variables para social-publisher en '$env'. Secret omitido."
        echo "  Requeridas: ANTHROPIC_API_KEY, UNSPLASH_ACCESS_KEY, META_PAGE_ID, META_IG_ACCOUNT_ID, META_PAGE_ACCESS_TOKEN"
        return 0
    fi

    echo "Creando Secret social-publisher-${env}..."
    kubectl create secret generic "social-publisher-${env}" \
        --from-literal=ANTHROPIC_API_KEY="${anthropic_key}" \
        --from-literal=UNSPLASH_ACCESS_KEY="${unsplash_key}" \
        --from-literal=META_PAGE_ID="${meta_page_id}" \
        --from-literal=META_IG_ACCOUNT_ID="${meta_ig_id}" \
        --from-literal=META_PAGE_ACCESS_TOKEN="${meta_token}" \
        -n "$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "OK — Secret social-publisher-${env} creado"
}

case $ENV in
    dev|pre|pro)
        create_secrets_for_env "$ENV"
        create_social_secrets_for_env "$ENV"
        ;;
    all)
        create_secrets_for_env "dev"
        create_secrets_for_env "pre"
        create_secrets_for_env "pro"
        create_social_secrets_for_env "dev"
        create_social_secrets_for_env "pre"
        create_social_secrets_for_env "pro"
        ;;
    *)
        echo "Uso: $0 [dev|pre|pro|all]"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Secrets creados exitosamente"
echo "=========================================="
echo ""
echo "Verificar: kubectl get secrets -n n8n-${ENV}"
