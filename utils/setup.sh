#!/bin/bash
set -e

# Validate required environment variables
if [ x${ELASTIC_PASSWORD} == x ]; then
  echo "Set the ELASTIC_PASSWORD environment variable in the .env file"
  exit 1
elif [ x${KIBANA_PASSWORD} == x ]; then
  echo "Set the KIBANA_PASSWORD environment variable in the .env file"
  exit 1
fi

# Create CA certificate if it doesn't exist
if [ ! -f config/certs/ca.zip ]; then
  echo "Creating CA"
  bin/elasticsearch-certutil ca --silent --pem -out config/certs/ca.zip
  unzip config/certs/ca.zip -d config/certs
fi

# Create certificates if they don't exist
if [ ! -f config/certs/certs.zip ]; then
  echo "Creating certs"
  echo -ne \
  "instances:\n"\
  "  - name: es01\n"\
  "    dns:\n"\
  "      - es01\n"\
  "      - localhost\n"\
  "    ip:\n"\
  "      - 127.0.0.1\n"\
  "  - name: kibana\n"\
  "    dns:\n"\
  "      - kibana\n"\
  "      - localhost\n"\
  "    ip:\n"\
  "      - 127.0.0.1\n"\
  "  - name: fleet-server\n"\
  "    dns:\n"\
  "      - fleet-server\n"\
  "      - localhost\n"\
  "    ip:\n"\
  "      - 127.0.0.1\n"\
  > config/certs/instances.yml

  bin/elasticsearch-certutil cert --silent --pem \
    -out config/certs/certs.zip \
    --in config/certs/instances.yml \
    --ca-cert config/certs/ca/ca.crt \
    --ca-key config/certs/ca/ca.key

  unzip config/certs/certs.zip -d config/certs
fi

# Set file permissions
echo "Setting file permissions"
chown -R root:root config/certs
find . -type d -exec chmod 750 \{\} \;
find . -type f -exec chmod 640 \{\} \;

# Wait for Elasticsearch availability
echo "Waiting for Elasticsearch availability"
until curl -s --cacert config/certs/ca/ca.crt https://es01:9200 | grep -q "missing authentication credentials"; do
  sleep 30
done

# Set kibana_system password
echo "Setting kibana_system password"
until curl -s -X POST \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" \
  https://es01:9200/_security/user/kibana_system/_password \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do
  sleep 10
done

echo "Waiting for Kibana to be ready..."
    until curl -s --cacert config/certs/ca/ca.crt https://kibana:5601 -o /dev/null 2>&1; do
      echo "Kibana not ready yet, retrying in 10s..."
      sleep 10
    done
    echo "Kibana is ready, configuring Fleet SSL..."

echo "All done!"
