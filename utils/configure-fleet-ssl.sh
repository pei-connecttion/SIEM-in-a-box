#!/bin/bash
set -e

# ============================================
# Fleet SSL Certificate Configuration Script
# Configures Fleet output with dynamic CA certificate
# ============================================

echo "==========================================="
echo "Fleet SSL Configuration Starting..."
echo "==========================================="



# --------------------------------------------
# 1. Extract CA Fingerprint
# --------------------------------------------
echo "[CERTS] Extracting CA fingerprint..."
CA_FINGERPRINT=$(openssl x509 -fingerprint -sha256 -noout -in config/certs/ca/ca.crt | sed 's/.*=//;s/://g')
echo "[CERTS] CA Fingerprint: $CA_FINGERPRINT"



# --------------------------------------------
# 2. Wait for Kibana to be ready
# --------------------------------------------
echo "[KIBANA] Waiting for Kibana..."
until curl -s -I --cacert config/certs/ca/ca.crt https://kibana:5601 | grep -q "HTTP/1.1 302"; do
  echo "[KIBANA] Not ready yet, waiting 10s..."
  sleep 10
done
echo "[KIBANA] Kibana is responding!"



# ============= Give Fleet plugin time to initialize =============
echo "[KIBANA] Waiting 10s for Fleet plugin to initialize..."
sleep 10
# =============================================================



# --------------------------------------------
# 10. Configure Fleet Output with SSL/Fingerprint
# --------------------------------------------

CONFIG_YAML="ssl:
  certificate_authorities:
  - |
$(cat config/certs/ca/ca.crt | sed 's/^/    /')"

CONFIG_YAML_ESCAPED=$(echo "$CONFIG_YAML" | awk '{printf "%s\\n", $0}')

OUTPUT_UPDATE=$(curl -s --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -X PUT "https://kibana:5601/api/fleet/outputs/fleet-default-output" \
  -d "{
    \"name\": \"default\",
    \"type\": \"elasticsearch\",
    \"hosts\": [\"https://es01:9200\"],
    \"is_default\": true,
    \"is_default_monitoring\": true,
    \"ca_trusted_fingerprint\": \"${CA_FINGERPRINT}\",
    \"config_yaml\": \"${CONFIG_YAML_ESCAPED}\"
  }")
echo "[FLEET] Output update response: $OUTPUT_UPDATE"



# --------------------------------------------
# 12. Create Service Token for Fleet Server
# --------------------------------------------

echo "[FLEET] Creating Fleet Server service token..."
SERVICE_TOKEN_JSON=$(curl -s --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -X POST "https://kibana:5601/api/fleet/service_tokens")

echo "[FLEET] Service token response: $SERVICE_TOKEN_JSON"

SERVICE_TOKEN=$(echo "$SERVICE_TOKEN_JSON" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -n "$SERVICE_TOKEN" ]; then
  printf "%s" "$SERVICE_TOKEN" > config/certs/fleet-service-token
  chmod 644 config/certs/fleet-service-token
  echo "[FLEET] Service token saved to config/certs/fleet-service-token"
else
  echo "[FLEET] Warning: Could not extract service token"
fi


echo "==========================================="
echo "Fleet SSL Configuration Complete!"
echo "==========================================="
