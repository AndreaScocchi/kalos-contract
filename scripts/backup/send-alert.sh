#!/usr/bin/env bash
# send-alert — email di avviso via Amazon SES, dal dominio già verificato per le notifiche.
# Vedi BACKUP.md.
#
#   scripts/backup/send-alert.sh "<oggetto>" "<testo>"
#
# Variabili: ALERT_EMAIL_TO (anche più indirizzi separati da virgola), ALERT_EMAIL_FROM,
# AWS_REGION e credenziali AWS (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).
# ALERT_DRY_RUN=1 stampa la richiesta invece di inviarla.
set -euo pipefail

subject="${1:?Uso: send-alert.sh <oggetto> <testo>}"
body="${2:?Uso: send-alert.sh <oggetto> <testo>}"
: "${ALERT_EMAIL_TO:?Serve ALERT_EMAIL_TO}" "${ALERT_EMAIL_FROM:?Serve ALERT_EMAIL_FROM}"

if [ -n "${GITHUB_RUN_ID:-}" ]; then
  body="$body

Dettagli dell'esecuzione: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
fi

request="$(jq -n --arg from "$ALERT_EMAIL_FROM" --arg to "$ALERT_EMAIL_TO" --arg subject "$subject" --arg body "$body" '{
  FromEmailAddress: $from,
  Destination: { ToAddresses: ($to | split(",") | map(gsub("^\\s+|\\s+$"; ""))) },
  Content: { Simple: {
    Subject: { Data: $subject, Charset: "UTF-8" },
    Body: { Text: { Data: $body, Charset: "UTF-8" } }
  } }
}')"

if [ "${ALERT_DRY_RUN:-0}" = 1 ]; then
  echo "$request"
  exit 0
fi

aws sesv2 send-email --region "${AWS_REGION:-eu-central-1}" --cli-input-json "$request" > /dev/null
echo "📧 Avviso inviato."
