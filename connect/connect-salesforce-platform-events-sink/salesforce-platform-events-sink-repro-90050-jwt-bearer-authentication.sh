#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
CONSUMER_KEY=${CONSUMER_KEY:-$3}
CONSUMER_PASSWORD=${CONSUMER_PASSWORD:-$4}
SECURITY_TOKEN=${SECURITY_TOKEN:-$5}
SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}

if [ -z "$SALESFORCE_USERNAME" ]
then
     logerror "SALESFORCE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_PASSWORD" ]
then
     logerror "SALESFORCE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


if [ -z "$CONSUMER_KEY" ]
then
     logerror "CONSUMER_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$CONSUMER_PASSWORD" ]
then
     logerror "CONSUMER_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SECURITY_TOKEN" ]
then
     logerror "SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


# https://medium.com/@tou_sfdx/salesforce-oauth-jwt-bearer-flow-cc70bfc626c2

# keytool -genkey -noprompt -alias salesforce-confluent -dname "CN=ca1.test.confluent.io/OU=TEST/O=CONFLUENT/L=PaloAlto/ST=Ca/C=US" -keystore salesforce-confluent.keystore.jks -keyalg RSA -storepass confluent -keypass confluent -deststoretype pkcs12
# keytool -keystore salesforce-confluent.keystore.jks -alias salesforce-confluent -export -file salesforce-confluent.crt -storepass confluent -keypass confluent -trustcacerts -noprompt

# $SALESFORCE_INSTANCE/services/oauth2/authorize?response_type=token&client_id=$CONSUMER_KEY_APP_WITH_JWT&redirect_uri=https://test.salesforce.com/services/oauth2/success

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-90050-jwt-bearer-authentication.yml"

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SECURITY_TOKEN\""

log "Send Platform Events"
docker exec sfdx-cli sh -c "sfdx force:apex:execute  -u \"$SALESFORCE_USERNAME\" -f \"/tmp/event.apex\""

log "Creating Salesforce Platform Events Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePlatformEventSourceConnector",
                    "kafka.topic": "sfdc-platform-events",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.platform.event.name" : "MyPlatformEvent__e",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$CONSUMER_KEY"'",
                    "salesforce.consumer.secret" : "'"$CONSUMER_PASSWORD"'",
                    "salesforce.initial.start" : "all",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-platform-events-source/config | jq .




sleep 10

log "Verify we have received the data in sfdc-platform-events topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic sfdc-platform-events --from-beginning --max-messages 2

log "Creating Salesforce Platform Events Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePlatformEventSinkConnector",
                    "topics": "sfdc-platform-events",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.platform.event.name" : "MyPlatformEvent__e",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$CONSUMER_KEY_APP_WITH_JWT"'",
                    "salesforce.consumer.secret" : "'"$CONSUMER_SECRET_APP_WITH_JWT"'",
                    "salesforce.jwt.keystore.path": "/tmp/salesforce-confluent.keystore.jks",
                    "salesforce.jwt.keystore.password": "confluent",
                    "salesforce.initial.start" : "all",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "transforms": "MaskField",
                    "transforms.MaskField.type": "org.apache.kafka.connect.transforms.MaskField$Value",
                    "transforms.MaskField.fields": "Message__c",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-platform-events-sink/config | jq .


sleep 10

log "Verify topic success-responses"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 2

# log "Verify topic error-responses"
# timeout 20 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1