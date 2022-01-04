#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


function trigger_rebalance () {
     set +e
     for port in 8083 18083 28083
     do
          worker_id=$(curl -s http://localhost:$port/connectors/hdfs2-sink-ha-kerberos/tasks/0/status | jq -r .worker_id)
          if [ "$worker_id" != "" ]
          then
               break
          fi
     done
     worker=$(echo $worker_id | cut -d ":" -f 1)
     log "Restart connect worker <${worker}> to trigger a rebalance"
     docker restart "$worker"
}

function wait_for_repro () {
     set +e
     MAX_WAIT=43200
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for Failed to APPEND_FILE to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     docker container logs connect2 >> /tmp/out.txt 2>&1
     docker container logs connect3 >> /tmp/out.txt 2>&1
     while ! grep "Failed to APPEND_FILE" /tmp/out.txt > /dev/null;
     do
          for c in connect connect2 connect3
          do
               # send requests
               seq -f "{\"f1\": \"value%g\"}" 50 | docker exec -i $c kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
          done

          trigger_rebalance
          sleep 30
          docker container logs connect > /tmp/out.txt 2>&1
          docker container logs connect2 >> /tmp/out.txt 2>&1
          docker container logs connect3 >> /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Failed to APPEND_FILE' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     set -e
     log "The problem has been reproduced !"
}

if [ ! -f ${DIR}/hadoop-2.7.4.tar.gz ]
then
     log "Getting hadoop-2.7.4.tar.gz"
     wget https://archive.apache.org/dist/hadoop/common/hadoop-2.7.4/hadoop-2.7.4.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.ha-kerberos-repro-rebalance.yml"

log "Wait 120 seconds while hadoop is installing"
sleep 120

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -chmod 777  /"

log "Add connect kerberos principal"
docker exec -i krb5 kadmin.local << EOF
addprinc -randkey connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days +allow_renewable connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days krbtgt/EXAMPLE.COM
modprinc -maxlife 11days connect/connect.kerberos-demo.local@EXAMPLE.COM
ktadd -k /connect.keytab connect/connect.kerberos-demo.local@EXAMPLE.COM
listprincs
EOF

log "Copy connect.keytab to connect container"
docker cp krb5:/connect.keytab .
docker cp connect.keytab connect:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/connect.keytab
fi

log "Copy connect.keytab to connect2 container"
docker cp connect.keytab connect2:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect2 chown appuser:appuser /tmp/connect.keytab
fi

log "Copy connect.keytab to connect3 container"
docker cp connect.keytab connect3:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect3 chown appuser:appuser /tmp/connect.keytab
fi

log "Creating HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "store.url":"hdfs://sh",
               "flush.size":"3",
               "hadoop.conf.dir":"/opt/hadoop/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "logs.dir":"/logs",
               "hdfs.authentication.kerberos": "true",
               "connect.hdfs.principal": "connect/connect.kerberos-demo.local@EXAMPLE.COM",
               "connect.hdfs.keytab": "/tmp/connect.keytab",
               "hdfs.namenode.principal": "nn/namenode1.kerberos-demo.local@EXAMPLE.COM",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs2-sink-ha-kerberos/config | jq .


log "Sending messages to topic test_hdfs"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect2 kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /topics/test_hdfs in HDFS"
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -ls /topics/test_hdfs"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/f1=value1/test_hdfs+0+0000000000+0000000000.avro /tmp"
docker cp namenode1:/tmp/test_hdfs+0+0000000000+0000000000.avro /tmp/

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000000.avro


wait_for_repro
