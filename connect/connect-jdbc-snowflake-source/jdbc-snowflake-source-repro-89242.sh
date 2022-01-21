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

PLAYGROUND_DB=PLAYGROUND_DB${TAG}
PLAYGROUND_DB=${PLAYGROUND_DB//[-._]/}

PLAYGROUND_WAREHOUSE=PLAYGROUND_WAREHOUSE${TAG}
PLAYGROUND_WAREHOUSE=${PLAYGROUND_WAREHOUSE//[-._]/}

PLAYGROUND_CONNECTOR_ROLE=PLAYGROUND_CONNECTOR_ROLE${TAG}
PLAYGROUND_CONNECTOR_ROLE=${PLAYGROUND_CONNECTOR_ROLE//[-._]/}

PLAYGROUND_USER=PLAYGROUND_USER${TAG}
PLAYGROUND_USER=${PLAYGROUND_USER//[-._]/}

if [ ! -f ${DIR}/snowflake-jdbc-3.13.4.jar ]
then
     log "Downloading snowflake-jdbc-3.13.4.jar"
     wget https://repo1.maven.org/maven2/net/snowflake/snowflake-jdbc/3.13.4/snowflake-jdbc-3.13.4.jar
fi

SNOWFLAKE_ACCOUNT_NAME=${SNOWFLAKE_ACCOUNT_NAME:-$1}
SNOWFLAKE_USERNAME=${SNOWFLAKE_USERNAME:-$2}
SNOWFLAKE_PASSWORD=${SNOWFLAKE_PASSWORD:-$3}

if [ -z "$SNOWFLAKE_ACCOUNT_NAME" ]
then
     logerror "SNOWFLAKE_ACCOUNT_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SNOWFLAKE_USERNAME" ]
then
     logerror "SNOWFLAKE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SNOWFLAKE_PASSWORD" ]
then
     logerror "SNOWFLAKE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

# https://<account_name>.<region_id>.snowflakecomputing.com:443
SNOWFLAKE_URL="https://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com"

# using v1 PBE-SHA1-RC4-128, see https://community.snowflake.com/s/article/Private-key-provided-is-invalid-or-not-supported-rsa-key-p8--data-isn-t-an-object-ID
# Create encrypted Private key - keep this safe, do not share!
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -v1 PBE-SHA1-RC4-128 -out snowflake_key.p8 -passout pass:confluent
# Generate public key from private key. You can share your public key.
openssl rsa -in snowflake_key.p8 -pubout -out snowflake_key.pub -passin pass:confluent

if [ -z "$CI" ]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod a+rw snowflake_key.p8
else
    # docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod a+rw snowflake_key.p8
    ls -lrt
fi

RSA_PUBLIC_KEY=$(grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC"|tr -d '\n')
RSA_PRIVATE_KEY=$(grep -v "BEGIN ENCRYPTED PRIVATE KEY" snowflake_key.p8 | grep -v "END ENCRYPTED PRIVATE KEY"|tr -d '\n')


log "Create a Snowflake DB"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
DROP DATABASE IF EXISTS $PLAYGROUND_DB;
CREATE OR REPLACE DATABASE $PLAYGROUND_DB COMMENT = 'Database for Docker Playground';
EOF

log "Create a Snowflake ROLE"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS $PLAYGROUND_CONNECTOR_ROLE;
CREATE ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE $PLAYGROUND_DB TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON DATABASE $PLAYGROUND_DB TO ACCOUNTADMIN;
GRANT USAGE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA $PLAYGROUND_DB.PUBLIC TO $PLAYGROUND_CONNECTOR_ROLE;
GRANT USAGE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE ACCOUNTADMIN;
GRANT CREATE TABLE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT CREATE STAGE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
GRANT CREATE PIPE ON SCHEMA $PLAYGROUND_DB.PUBLIC TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
EOF

log "Create a Snowflake WAREHOUSE (for admin purpose as KafkaConnect is Serverless)"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE SYSADMIN;
CREATE OR REPLACE WAREHOUSE $PLAYGROUND_WAREHOUSE
  WAREHOUSE_SIZE = 'XSMALL'
  WAREHOUSE_TYPE = 'STANDARD'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 1
  SCALING_POLICY = 'STANDARD'
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for Kafka Playground';
GRANT USAGE ON WAREHOUSE $PLAYGROUND_WAREHOUSE TO ROLE $PLAYGROUND_CONNECTOR_ROLE;
EOF

log "Create a Snowflake USER"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE USERADMIN;
DROP USER IF EXISTS $PLAYGROUND_USER;
CREATE USER $PLAYGROUND_USER
 PASSWORD = 'Password123!'
 LOGIN_NAME = $PLAYGROUND_USER
 DISPLAY_NAME = $PLAYGROUND_USER
 DEFAULT_WAREHOUSE = $PLAYGROUND_WAREHOUSE
 DEFAULT_ROLE = $PLAYGROUND_CONNECTOR_ROLE
 DEFAULT_NAMESPACE = $PLAYGROUND_DB
 MUST_CHANGE_PASSWORD = FALSE
 RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY";
USE ROLE SECURITYADMIN;
GRANT ROLE $PLAYGROUND_CONNECTOR_ROLE TO USER $PLAYGROUND_USER;
EOF

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Create table foo"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
create or replace sequence seq1;
create or replace table FOO (id number default seq1.nextval, f1 string, update_ts timestamp default current_timestamp());
insert into FOO (f1) values ('value1');
insert into FOO (f1) values ('value2');
insert into FOO (f1) values ('value3');
EOF


# https://docs.snowflake.com/en/user-guide/jdbc-configure.html#jdbc-driver-connection-string
CONNECTION_URL="jdbc:snowflake://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com/?warehouse=$PLAYGROUND_WAREHOUSE&db=$PLAYGROUND_DB&role=$PLAYGROUND_CONNECTOR_ROLE&schema=PUBLIC&user=$PLAYGROUND_USER&private_key_file=/tmp/snowflake_key.p8&private_key_file_pwd=confluent&tracing=ALL"
log "Creating JDBC Snowflake Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "'"$CONNECTION_URL"'",
               "table.whitelist": "FOO",
               "table.types": "TABLE",
               "mode": "timestamp",
               "timestamp.column.name": "UPDATE_TS",
               "timestamp.delay.interval.ms": "1000",
               "table.poll.interval.ms": "3600000",
               "topic.prefix": "snowflake-",
               "validate.non.null":"false",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/jdbc-snowflake-source/config | jq .

sleep 15

log "Verifying topic snowflake-FOO"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic snowflake-FOO --from-beginning --max-messages 3

# [2022-01-21 10:30:54,560] INFO [jdbc-snowflake-source|task-0] Begin using SQL query: SELECT * FROM "PLAYGROUNDDB701"."PUBLIC"."FOO" WHERE "PLAYGROUNDDB701"."PUBLIC"."FOO"."UPDATE_TS" > ? AND "PLAYGROUNDDB701"."PUBLIC"."FOO"."UPDATE_TS" < ? ORDER BY "PLAYGROUNDDB701"."PUBLIC"."FOO"."UPDATE_TS" ASC (io.confluent.connect.jdbc.source.TableQuerier:164)


log "insert more records table foo"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
USE ROLE $PLAYGROUND_CONNECTOR_ROLE;
USE DATABASE $PLAYGROUND_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE $PLAYGROUND_WAREHOUSE;
insert into FOO (f1) values ('value4');
insert into FOO (f1) values ('value5');
insert into FOO (f1) values ('value6');
EOF

log "Verifying topic snowflake-FOO after 3 inserts"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic snowflake-FOO --from-beginning --max-messages 6

# without "table.poll.interval.ms": "3600000",
# {"ID":{"long":1},"F1":{"string":"value1"},"UPDATE_TS":{"long":1642743757732}}
# {"ID":{"long":2},"F1":{"string":"value2"},"UPDATE_TS":{"long":1642743758696}}
# {"ID":{"long":3},"F1":{"string":"value3"},"UPDATE_TS":{"long":1642743759580}}
# {"ID":{"long":1},"F1":{"string":"value1"},"UPDATE_TS":{"long":1642743757732}}
# {"ID":{"long":2},"F1":{"string":"value2"},"UPDATE_TS":{"long":1642743758696}}
# {"ID":{"long":3},"F1":{"string":"value3"},"UPDATE_TS":{"long":1642743759580}}