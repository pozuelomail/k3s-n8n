#!/bin/bash
set -euo pipefail

# ─── Variables ────────────────────────────────────────────────────────────────
BASE_URL="https://n8n.qforexwin.com/api/v1"
WEBHOOK_BASE="https://n8n.qforexwin.com/webhook"
API_KEY="${N8N_PRO_API_KEY:?Exporta N8N_PRO_API_KEY (Settings → API en n8n)}"
WF_ID="ybbXr5j5kwSAjtin"
WEBHOOK_PATH="crypto-prices"

# ─── Helpers ──────────────────────────────────────────────────────────────────
api() {
  local method="$1"; shift
  curl -s -X "$method" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -H "Content-Type: application/json" \
    "$@"
}

section() { echo -e "\n\033[1;34m══ $1 ══\033[0m"; }

# ─── Operaciones ──────────────────────────────────────────────────────────────
# Nota: la API pública de n8n 1.x no tiene endpoint /run.
# Los workflows se disparan vía su webhook URL una vez activados.

section "1. Obtener workflow"
api GET "$BASE_URL/workflows/$WF_ID" \
  | jq '{id, name, active, nodes: [.nodes[] | {name, type}]}'

section "2. Activar workflow"
# PATCH no está soportado en 1.x; usar el endpoint dedicado
api POST "$BASE_URL/workflows/$WF_ID/activate" \
  | jq '{id, name, active}'

section "3. Disparar ejecución vía webhook"
echo "POST $WEBHOOK_BASE/$WEBHOOK_PATH"
curl -s -X POST "$WEBHOOK_BASE/$WEBHOOK_PATH" \
  -H "Content-Type: application/json" \
  -d '{"source": "api-test"}' | jq .

section "4. Consultar última ejecución"
sleep 2
api GET "$BASE_URL/executions?workflowId=$WF_ID&limit=1" \
  | jq '.data[] | {id, status, mode, startedAt, stoppedAt}'

section "5. Desactivar workflow"
api POST "$BASE_URL/workflows/$WF_ID/deactivate" \
  | jq '{id, name, active}'

section "6. Borrar workflow"
read -r -p "¿Borrar el workflow $WF_ID? [s/N] " confirm
if [[ "${confirm,,}" == "s" ]]; then
  api DELETE "$BASE_URL/workflows/$WF_ID" | jq .
  echo "Workflow eliminado."
else
  echo "Borrado cancelado."
fi
