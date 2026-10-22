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

FB_RESP=$(curl -s -H "Authorization: Bearer ${META_PAGE_ACCESS_TOKEN}" "https://graph.facebook.com/v19.0/${META_PAGE_ID}?fields=name,id")
FB_NAME=$(echo "$FB_RESP" | jq -r '.name // empty')
FB_ERR=$(echo "$FB_RESP"  | jq -r '.error.message // empty')

if [[ -n "$FB_NAME" ]]; then
  ok "Facebook Page: $FB_NAME (ID: $META_PAGE_ID)"
else
  err "Error accediendo a la Page: ${FB_ERR:-respuesta inesperada}"
  echo "  Respuesta: $FB_RESP"
  exit 1
fi

IG_RESP=$(curl -s -H "Authorization: Bearer ${META_PAGE_ACCESS_TOKEN}" "https://graph.facebook.com/v19.0/${META_IG_ACCOUNT_ID}?fields=name,username")
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

# ─── Paso 5: Credenciales en n8n ──────────────────────────────────────────────
# Las claves se guardan cifradas como credenciales de n8n y solo las usa este flujo.
# Nada de variables de entorno: N8N_BLOCK_ENV_ACCESS_IN_NODE=true impide leerlas desde los flujos.
section "5. Crear o actualizar credenciales en n8n"

upsert_cred() {   # nombre, nombre de cabecera, valor  → imprime el id
  local name="$1" header="$2" value="$3" id body
  body=$(jq -n --arg n "$header" --arg v "$value" '{name:$n, value:$v}')
  id=$(n8n_api GET "$N8N_BASE/credentials?limit=250" | jq -r --arg n "$name" '.data[]? | select(.name==$n) | .id' | head -1)
  if [[ -n "$id" ]]; then
    n8n_api PATCH "$N8N_BASE/credentials/$id" -d "$(jq -n --argjson d "$body" '{data:$d}')" >/dev/null
  else
    id=$(n8n_api POST "$N8N_BASE/credentials" \
      -d "$(jq -n --arg nm "$name" --argjson d "$body" '{name:$nm, type:"httpHeaderAuth", data:$d}')" | jq -r '.id // empty')
  fi
  [[ -n "$id" ]] || { err "No se pudo crear la credencial «$name»"; exit 1; }
  echo "$id"
}

CRED_ANTHROPIC=$(upsert_cred "Anthropic API (social-publisher)" "x-api-key" "$ANTHROPIC_API_KEY")
CRED_UNSPLASH=$(upsert_cred "Unsplash (social-publisher)" "Authorization" "Client-ID $UNSPLASH_ACCESS_KEY")
CRED_META=$(upsert_cred "Meta Page Token (social-publisher)" "Authorization" "Bearer $META_PAGE_ACCESS_TOKEN")
ok "Credenciales listas"

# ─── Paso 6: Importar workflow en n8n ─────────────────────────────────────────
section "6. Importar workflow en n8n"

WF_PAYLOAD=$(sed -e "s/__CRED_ANTHROPIC__/${CRED_ANTHROPIC}/g" -e "s/__CRED_UNSPLASH__/${CRED_UNSPLASH}/g" \
  -e "s/__CRED_META__/${CRED_META}/g" -e "s/__META_PAGE_ID__/${META_PAGE_ID}/g" \
  -e "s/__META_IG_ACCOUNT_ID__/${META_IG_ACCOUNT_ID}/g" "$WORKFLOW_JSON")
echo "$WF_PAYLOAD" | jq -e . >/dev/null

EXISTING_WF=$(n8n_api GET "$N8N_BASE/workflows" | jq -r '.data[] | select(.name == "Social Media Publisher (FB + IG)") | .id' 2>/dev/null || echo "")

if [[ -n "$EXISTING_WF" ]]; then
  ok "Workflow ya existe (ID: $EXISTING_WF) — actualizando..."
  n8n_api PUT "$N8N_BASE/workflows/$EXISTING_WF" -d "$WF_PAYLOAD" | jq '{id, name}'
  WF_ID="$EXISTING_WF"
else
  CREATED=$(n8n_api POST "$N8N_BASE/workflows" -d "$WF_PAYLOAD")
  WF_ID=$(echo "$CREATED" | jq -r '.id')
  ok "Workflow creado (ID: $WF_ID)"
fi

# ─── Paso 7: Activar el workflow ──────────────────────────────────────────────
section "7. Activar workflow"

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
