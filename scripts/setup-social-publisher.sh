#!/bin/bash
# ============================================
# Setup: Social Media Publisher en n8n
# Uso: source ~/.env && ./scripts/setup-social-publisher.sh [pro|pre|dev]
#
# Variables requeridas en ~/.env:
#   ANTHROPIC_API_KEY          — clave de API de Anthropic (Claude)
#   UNSPLASH_ACCESS_KEY        — Access Key de Unsplash Developer
#   META_PAGE_ID               — ID numérico de tu Facebook Page
#   META_IG_ACCOUNT_ID         — ID numérico de tu cuenta Instagram Business
#   META_PAGE_ACCESS_TOKEN     — Page Access Token (no expira si se genera desde long-lived user token)
#   N8N_PRO_API_KEY            — API Key de n8n (Settings → API en la UI)
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV=${1:-pro}
NAMESPACE="n8n-${ENV}"
N8N_BASE="https://n8n.qforexwin.com/api/v1"
WORKFLOW_JSON="${REPO_ROOT}/manifests/social-publisher-workflow.json"

# ─── Helpers ──────────────────────────────────────────────────────────────────
section() { echo -e "\n\033[1;34m══ $1 ══\033[0m"; }
ok()      { echo -e "  \033[0;32m✓\033[0m $1"; }
err()     { echo -e "  \033[0;31m✗\033[0m $1"; }

n8n_api() {
  local method="$1"; shift
  curl -s -X "$method" \
    -H "X-N8N-API-KEY: ${N8N_PRO_API_KEY}" \
    -H "Content-Type: application/json" \
    "$@"
}

# ─── Paso 1: Verificar variables de entorno ───────────────────────────────────
section "1. Verificar credenciales en ~/.env"

MISSING=()
for var in ANTHROPIC_API_KEY UNSPLASH_ACCESS_KEY META_PAGE_ID META_IG_ACCOUNT_ID META_PAGE_ACCESS_TOKEN N8N_PRO_API_KEY; do
  if [[ -z "${!var:-}" ]]; then
    MISSING+=("$var")
    err "$var — NO definida"
  else
    ok "$var — OK"
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "ERROR: Añade las variables faltantes a ~/.env y vuelve a ejecutar."
  echo "  Consulta el README de setup: scripts/setup-social-publisher.sh --guide"
  exit 1
fi

# ─── Paso 2: Verificar conectividad con Meta ──────────────────────────────────
section "2. Verificar token de Meta"

FB_RESP=$(curl -s "https://graph.facebook.com/v19.0/${META_PAGE_ID}?fields=name,id&access_token=${META_PAGE_ACCESS_TOKEN}")
FB_NAME=$(echo "$FB_RESP" | jq -r '.name // empty')
FB_ERR=$(echo "$FB_RESP"  | jq -r '.error.message // empty')

if [[ -n "$FB_NAME" ]]; then
  ok "Facebook Page: $FB_NAME (ID: $META_PAGE_ID)"
else
  err "Error accediendo a la Page: ${FB_ERR:-respuesta inesperada}"
  echo "  Respuesta: $FB_RESP"
  exit 1
fi

IG_RESP=$(curl -s "https://graph.facebook.com/v19.0/${META_IG_ACCOUNT_ID}?fields=name,username&access_token=${META_PAGE_ACCESS_TOKEN}")
IG_USER=$(echo "$IG_RESP" | jq -r '.username // .name // empty')
IG_ERR=$(echo "$IG_RESP"  | jq -r '.error.message // empty')

if [[ -n "$IG_USER" ]]; then
  ok "Instagram Business: @${IG_USER} (ID: $META_IG_ACCOUNT_ID)"
else
  err "Error accediendo a la cuenta IG: ${IG_ERR:-respuesta inesperada}"
  echo "  Respuesta: $IG_RESP"
  exit 1
fi

# ─── Paso 3: Verificar Unsplash ───────────────────────────────────────────────
section "3. Verificar Unsplash API Key"

UNSPLASH_RESP=$(curl -s "https://api.unsplash.com/photos/random" \
  -H "Authorization: Client-ID ${UNSPLASH_ACCESS_KEY}")
UNSPLASH_ID=$(echo "$UNSPLASH_RESP" | jq -r '.id // empty')

if [[ -n "$UNSPLASH_ID" ]]; then
  ok "Unsplash API Key válida"
else
  UNSPLASH_ERR=$(echo "$UNSPLASH_RESP" | jq -r '.errors[0] // .error // "error desconocido"')
  err "Unsplash: $UNSPLASH_ERR"
  exit 1
fi

# ─── Paso 4: Verificar Anthropic ──────────────────────────────────────────────
section "4. Verificar Anthropic API Key"

CLAUDE_RESP=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"Di hola"}]}')
CLAUDE_TEXT=$(echo "$CLAUDE_RESP" | jq -r '.content[0].text // empty')
CLAUDE_ERR=$(echo "$CLAUDE_RESP"  | jq -r '.error.message // empty')

if [[ -n "$CLAUDE_TEXT" ]]; then
  ok "Anthropic API Key válida"
else
  err "Anthropic: ${CLAUDE_ERR:-error desconocido}"
  exit 1
fi

# ─── Paso 5: Crear secret en Kubernetes ───────────────────────────────────────
section "5. Crear secret social-publisher-${ENV} en Kubernetes"

kubectl create secret generic "social-publisher-${ENV}" \
  --from-literal=ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
  --from-literal=UNSPLASH_ACCESS_KEY="${UNSPLASH_ACCESS_KEY}" \
  --from-literal=META_PAGE_ID="${META_PAGE_ID}" \
  --from-literal=META_IG_ACCOUNT_ID="${META_IG_ACCOUNT_ID}" \
  --from-literal=META_PAGE_ACCESS_TOKEN="${META_PAGE_ACCESS_TOKEN}" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

ok "Secret creado"

# ─── Paso 6: Redeploy para inyectar el secret como env vars ───────────────────
section "6. Redeploy de n8n (inyectar credenciales vía envFrom)"

echo "  Ejecutando: ./scripts/deploy.sh ${ENV}"
echo ""
(cd "$REPO_ROOT" && bash scripts/deploy.sh "$ENV")

# ─── Paso 7: Importar workflow en n8n ─────────────────────────────────────────
section "7. Importar workflow en n8n"

# Verificar si ya existe
EXISTING_WF=$(n8n_api GET "$N8N_BASE/workflows" | jq -r '.data[] | select(.name == "Social Media Publisher (FB + IG)") | .id' 2>/dev/null || echo "")

if [[ -n "$EXISTING_WF" ]]; then
  ok "Workflow ya existe (ID: $EXISTING_WF) — actualizando..."
  WF_PAYLOAD=$(cat "$WORKFLOW_JSON")
  n8n_api PUT "$N8N_BASE/workflows/$EXISTING_WF" -d "$WF_PAYLOAD" | jq '{id, name}'
  WF_ID="$EXISTING_WF"
else
  WF_PAYLOAD=$(cat "$WORKFLOW_JSON")
  CREATED=$(n8n_api POST "$N8N_BASE/workflows" -d "$WF_PAYLOAD")
  WF_ID=$(echo "$CREATED" | jq -r '.id')
  ok "Workflow creado (ID: $WF_ID)"
fi

# ─── Paso 8: Activar el workflow ──────────────────────────────────────────────
section "8. Activar workflow"

n8n_api POST "$N8N_BASE/workflows/$WF_ID/activate" | jq '{id, name, active}'
ok "Workflow activo — publicará L-V a las 10:00"

# ─── Resumen ──────────────────────────────────────────────────────────────────
echo ""
echo -e "\033[1;32m══════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  Setup completado con éxito\033[0m"
echo -e "\033[1;32m══════════════════════════════════════════\033[0m"
echo ""
echo "  Workflow ID : $WF_ID"
echo "  Programación: L-V a las 10:00"
echo "  Ver en n8n  : https://n8n.qforexwin.com/workflow/$WF_ID"
echo ""
echo "  Para ejecutar manualmente desde el webhook de prueba:"
echo "  curl -s https://n8n.qforexwin.com/webhook-test/social-publisher | jq ."
echo ""
