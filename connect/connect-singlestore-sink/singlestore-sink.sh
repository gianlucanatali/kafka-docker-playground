#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

singlestore-wait-start() {
  log "Waiting for SingleStore to start..."
  while true; do
      if docker exec singlestore memsql -u root -proot -e "select 1" >/dev/null 2>/dev/null; then
          break
      fi
      log "."
      sleep 0.2
  done
  log "Success!"
}

if [ ! -f ${DIR}/singlestore-jdbc-client-1.0.1.jar ]
then
     # install deps
     log "Getting singlestore-jdbc-client-1.0.1.jar"
     wget https://repo.maven.apache.org/maven2/com/singlestore/singlestore-jdbc-client/1.0.1/singlestore-jdbc-client-1.0.1.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Starting singlestore cluster"
docker start singlestore

singlestore-wait-start

log "Creating 'test' SingleStore database..."
docker exec singlestore memsql -u root -proot -e "create database if not exists test;"

log "Sending messages to topic mytable"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytable --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Creating Singlestore sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"com.singlestore.kafka.SingleStoreSinkConnector",
               "tasks.max":"1",
               "topics":"mytable",
               "connection.ddlEndpoint" : "singlestore:3306",
               "connection.database" : "test",
               "connection.user" : "root",
               "connection.password" : "root"
          }' \
     http://localhost:8083/connectors/singlestore-sink/config | jq .

sleep 10

log "Check data is in Singlestore"
docker exec -i singlestore memsql -u root -proot > /tmp/result.log  2>&1 <<-EOF
use test;
show tables;
select * from mytable;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log
