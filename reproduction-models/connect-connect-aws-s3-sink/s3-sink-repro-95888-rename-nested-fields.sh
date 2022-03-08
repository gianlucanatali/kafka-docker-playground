#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

for component in producer-repro-95888
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-95888-rename-nested-fields.yml"

AWS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}

AWS_REGION=$(aws configure get region | tr '\r' '\n')
log "Creating bucket name <$AWS_BUCKET_NAME>, if required"
set +e
aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME --recursive --region $AWS_REGION
set -e

log "Creating S3 Sink connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "customer_avro",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "s3.part.size": 52428801,
               "flush.size": "3",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
               "schema.compatibility": "NONE",
               "transforms": "flatten.RenameField",
               "transforms.flatten.delimiter": ".",
               "transforms.flatten.type": "org.apache.kafka.connect.transforms.Flatten$Value",
               "transforms.RenameField.type":"org.apache.kafka.connect.transforms.ReplaceField$Value",
               "transforms.RenameField.renames": "TmfOutput.schemaVersion:TmfOutput.schemaVersion1"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .


               "transforms": "RenameField",
               "transforms.flatten.delimiter": ".",
               "transforms.flatten.type": "org.apache.kafka.connect.transforms.Flatten$Value",
               "transforms.RenameField.type":"org.apache.kafka.connect.transforms.ReplaceField$Value",
               "transforms.RenameField.renames": "TmfOutput.schemaVersion:schemaVersion1"

log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-95888 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing objects of in S3"
aws s3api list-objects --bucket "$AWS_BUCKET_NAME"
