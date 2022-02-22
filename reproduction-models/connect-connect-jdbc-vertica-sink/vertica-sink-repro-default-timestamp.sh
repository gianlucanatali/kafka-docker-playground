#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     log "Getting vertica-jdbc.jar from vertica-client-10.0.1-0.x86_64.tar.gz"
     wget https://www.vertica.com/client_drivers/10.0.x/10.0.1-0/vertica-client-10.0.1-0.x86_64.tar.gz
     tar xvfz ${DIR}/vertica-client-10.0.1-0.x86_64.tar.gz
     cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
     rm -rf ${DIR}/opt
     rm -f ${DIR}/vertica-client-10.0.1-0.x86_64.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Create the table and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
create table mytable(f1 varchar(20),dwhCreationDate timestamp NOT NULL default(sysdate));
EOF

sleep 2

log "Sending messages to topic mytable"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytable --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Creating JDBC Vertica sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max" : "1",
                    "connection.url": "jdbc:vertica://vertica:5433/docker?user=dbadmin&password=",
                    "auto.create": "false",
                    "auto.evolve": "false",
                    "topics": "mytable"
          }' \
     http://localhost:8083/connectors/jdbc-vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytable;
EOF

#    f1    |      dwhCreationDate
# ---------+----------------------------
#  value1  | 2020-07-30 15:10:17.216578
#  value2  | 2020-07-30 15:10:17.216578
#  value3  | 2020-07-30 15:10:17.216578
#  value4  | 2020-07-30 15:10:17.216578
#  value5  | 2020-07-30 15:10:17.216578
#  value6  | 2020-07-30 15:10:17.216578
#  value7  | 2020-07-30 15:10:17.216578
#  value8  | 2020-07-30 15:10:17.216578
#  value9  | 2020-07-30 15:10:17.216578
#  value10 | 2020-07-30 15:10:17.216578
# (10 rows)
