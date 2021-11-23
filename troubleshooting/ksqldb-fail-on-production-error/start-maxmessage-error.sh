#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
unset DISABLE_KSQLDB

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.maxmessage-error.yml"

log "Create the input topic with a stream"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF
CREATE STREAM SENSORS_RAW (id VARCHAR, timestamp VARCHAR, enabled BOOLEAN)
    WITH (KAFKA_TOPIC = 'SENSORS_RAW',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1);

CREATE STREAM SENSORS AS
    SELECT
        ID, TIMESTAMP, ENABLED
    FROM SENSORS_RAW
    PARTITION BY ID;
EOF

log "Produce a big message to the input topic SENSORS_RAW"
bigmessage=$(cat bigmessage.txt)
echo "{\"id\": \"$bigmessage\", \"timestamp\": \"2020-01-15 02:20:30\", \"enabled\": true}" | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic SENSORS_RAW --compression-codec=snappy --producer-property max.request.size=2097172
echo "{\"id\": \"$bigmessage\", \"timestamp\": \"2020-01-15 02:20:30\", \"enabled\": true}" | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic SENSORS_RAW --compression-codec=snappy --producer-property max.request.size=2097172

sleep 60

log "Checking topic ksql_processing_log"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic ksql_processing_log --from-beginning --max-messages 1

# {"level":"ERROR","logger":"processing.CSAS_SENSORS_3","time":1637601815511,"message":{"type":2,"deserializationError":null,"recordProcessingError":null,"productionError":{"errorMessage":"The message is 1048660 bytes when serialized which is larger than 1048576, which is the value of the max.request.size configuration."},"serializationError":null,"kafkaStreamsThreadError":null}}

# With KSQL_KSQL_FAIL_ON_PRODUCTION_ERROR: "true"

# [2021-11-23 09:19:40,498] ERROR Unhandled exception caught in streams thread _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-1. (UNKNOWN) (io.confluent.ksql.util.QueryMetadataImpl)
# org.apache.kafka.streams.errors.StreamsException: Error encountered sending record to topic SENSORS for task 0_0 due to:
# org.apache.kafka.common.errors.RecordTooLargeException: The message is 1048660 bytes when serialized which is larger than 1048576, which is the value of the max.request.size configuration.
# Exception handler choose to FAIL the processing, no more records would be sent.
#         at org.apache.kafka.streams.processor.internals.RecordCollectorImpl.recordSendError(RecordCollectorImpl.java:226)
#         at org.apache.kafka.streams.processor.internals.RecordCollectorImpl.lambda$send$0(RecordCollectorImpl.java:196)
#         at org.apache.kafka.clients.producer.KafkaProducer.doSend(KafkaProducer.java:986)
#         at org.apache.kafka.clients.producer.KafkaProducer.send(KafkaProducer.java:889)
#         at org.apache.kafka.streams.processor.internals.StreamsProducer.send(StreamsProducer.java:210)
#         at org.apache.kafka.streams.processor.internals.RecordCollectorImpl.send(RecordCollectorImpl.java:182)
#         at org.apache.kafka.streams.processor.internals.RecordCollectorImpl.send(RecordCollectorImpl.java:139)
#         at org.apache.kafka.streams.processor.internals.SinkNode.process(SinkNode.java:85)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forwardInternal(ProcessorContextImpl.java:253)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:232)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:191)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:172)
#         at org.apache.kafka.streams.kstream.internals.KStreamTransformValues$KStreamTransformValuesProcessor.process(KStreamTransformValues.java:61)
#         at org.apache.kafka.streams.processor.internals.ProcessorAdapter.process(ProcessorAdapter.java:71)
#         at org.apache.kafka.streams.processor.internals.ProcessorNode.process(ProcessorNode.java:146)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forwardInternal(ProcessorContextImpl.java:253)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:232)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:191)
#         at org.apache.kafka.streams.kstream.internals.KStreamMap$KStreamMapProcessor.process(KStreamMap.java:45)
#         at org.apache.kafka.streams.processor.internals.ProcessorNode.process(ProcessorNode.java:146)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forwardInternal(ProcessorContextImpl.java:253)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:232)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:191)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:172)
#         at org.apache.kafka.streams.kstream.internals.KStreamTransformValues$KStreamTransformValuesProcessor.process(KStreamTransformValues.java:61)
#         at org.apache.kafka.streams.processor.internals.ProcessorAdapter.process(ProcessorAdapter.java:71)
#         at org.apache.kafka.streams.processor.internals.ProcessorNode.process(ProcessorNode.java:146)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forwardInternal(ProcessorContextImpl.java:253)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:232)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:191)
#         at org.apache.kafka.streams.processor.internals.SourceNode.process(SourceNode.java:84)
#         at org.apache.kafka.streams.processor.internals.StreamTask.lambda$process$1(StreamTask.java:731)
#         at org.apache.kafka.streams.processor.internals.metrics.StreamsMetricsImpl.maybeMeasureLatency(StreamsMetricsImpl.java:769)
#         at org.apache.kafka.streams.processor.internals.StreamTask.process(StreamTask.java:731)
#         at org.apache.kafka.streams.processor.internals.TaskManager.process(TaskManager.java:1193)
#         at org.apache.kafka.streams.processor.internals.StreamThread.runOnce(StreamThread.java:753)
#         at org.apache.kafka.streams.processor.internals.StreamThread.runLoop(StreamThread.java:583)
#         at org.apache.kafka.streams.processor.internals.StreamThread.run(StreamThread.java:555)
# Caused by: org.apache.kafka.common.errors.RecordTooLargeException: The message is 1048660 bytes when serialized which is larger than 1048576, which is the value of the max.request.size configuration.

# [2021-11-23 09:20:10,464] INFO Restarting query CSAS_SENSORS_3 (attempt #1) (io.confluent.ksql.util.QueryMetadataImpl)
# [2021-11-23 09:20:10,467] ERROR {"type":4,"deserializationError":null,"recordProcessingError":null,"productionError":null,"serializationError":null,"kafkaStreamsThreadError":{"errorMessage":"Unhandled exception caught in streams thread","threadName":"_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-1","cause":["Error encountered sending record to topic SENSORS for task 0_0 due to:\norg.apache.kafka.common.errors.RecordTooLargeException: The message is 1048660 bytes when serialized which is larger than 1048576, which is the value of the max.request.size configuration.\nException handler choose to FAIL the processing, no more records would be sent.","The message is 1048660 bytes when serialized which is larger than 1048576, which is the value of the max.request.size configuration."]}} (processing.CSAS_SENSORS_3.ksql.logger.thread.exception.uncaught)
# [2021-11-23 09:20:10,468] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-1] Informed to shut down (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:10,468] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-1] State transition from RUNNING to PENDING_SHUTDOWN (org.apache.kafka.streams.processor.internals.StreamThread)


# [2021-11-23 09:20:10,612] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-1] State transition from PENDING_SHUTDOWN to DEAD (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:10,612] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-1] Shutdown complete (org.apache.kafka.streams.processor.internals.StreamThread)
# Exception in thread "_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-1" org.apache.kafka.streams.errors.StreamsException: Error encountered sending record to topic SENSORS for task 0_0 due to:
# org.apache.kafka.common.errors.RecordTooLargeException: The message is 1048660 bytes when serialized which is larger than 1048576, which is the value of the max.request.size configuration.
# Exception handler choose to FAIL the processing, no more records would be sent.
#         at org.apache.kafka.streams.processor.internals.RecordCollectorImpl.recordSendError(RecordCollectorImpl.java:226)
#         at org.apache.kafka.streams.processor.internals.RecordCollectorImpl.lambda$send$0(RecordCollectorImpl.java:196)
#         at org.apache.kafka.clients.producer.KafkaProducer.doSend(KafkaProducer.java:986)
#         at org.apache.kafka.clients.producer.KafkaProducer.send(KafkaProducer.java:889)
#         at org.apache.kafka.streams.processor.internals.StreamsProducer.send(StreamsProducer.java:210)
#         at org.apache.kafka.streams.processor.internals.RecordCollectorImpl.send(RecordCollectorImpl.java:182)
#         at org.apache.kafka.streams.processor.internals.RecordCollectorImpl.send(RecordCollectorImpl.java:139)
#         at org.apache.kafka.streams.processor.internals.SinkNode.process(SinkNode.java:85)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forwardInternal(ProcessorContextImpl.java:253)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:232)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:191)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:172)
#         at org.apache.kafka.streams.kstream.internals.KStreamTransformValues$KStreamTransformValuesProcessor.process(KStreamTransformValues.java:61)
#         at org.apache.kafka.streams.processor.internals.ProcessorAdapter.process(ProcessorAdapter.java:71)
#         at org.apache.kafka.streams.processor.internals.ProcessorNode.process(ProcessorNode.java:146)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forwardInternal(ProcessorContextImpl.java:253)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:232)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:191)
#         at org.apache.kafka.streams.kstream.internals.KStreamMap$KStreamMapProcessor.process(KStreamMap.java:45)
#         at org.apache.kafka.streams.processor.internals.ProcessorNode.process(ProcessorNode.java:146)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forwardInternal(ProcessorContextImpl.java:253)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:232)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:191)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:172)
#         at org.apache.kafka.streams.kstream.internals.KStreamTransformValues$KStreamTransformValuesProcessor.process(KStreamTransformValues.java:61)
#         at org.apache.kafka.streams.processor.internals.ProcessorAdapter.process(ProcessorAdapter.java:71)
#         at org.apache.kafka.streams.processor.internals.ProcessorNode.process(ProcessorNode.java:146)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forwardInternal(ProcessorContextImpl.java:253)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:232)
#         at org.apache.kafka.streams.processor.internals.ProcessorContextImpl.forward(ProcessorContextImpl.java:191)
#         at org.apache.kafka.streams.processor.internals.SourceNode.process(SourceNode.java:84)
#         at org.apache.kafka.streams.processor.internals.StreamTask.lambda$process$1(StreamTask.java:731)
#         at org.apache.kafka.streams.processor.internals.metrics.StreamsMetricsImpl.maybeMeasureLatency(StreamsMetricsImpl.java:769)
#         at org.apache.kafka.streams.processor.internals.StreamTask.process(StreamTask.java:731)
#         at org.apache.kafka.streams.processor.internals.TaskManager.process(TaskManager.java:1193)
#         at org.apache.kafka.streams.processor.internals.StreamThread.runOnce(StreamThread.java:753)
#         at org.apache.kafka.streams.processor.internals.StreamThread.runLoop(StreamThread.java:583)
#         at org.apache.kafka.streams.processor.internals.StreamThread.run(StreamThread.java:555)
# Caused by: org.apache.kafka.common.errors.RecordTooLargeException: The message is 1048660 bytes when serialized which is larger than 1048576, which is the value of the max.request.size configuration.
# [2021-11-23 09:20:10,633] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5] Processed 0 total records, ran 0 punctuators, and committed 0 total tasks since the last update (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:10,640] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Request joining group due to: group is already rebalancing (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:10,640] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Request joining group due to: group is already rebalancing (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:10,642] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] (Re-)joining group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:10,642] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] (Re-)joining group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:10,644] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Request joining group due to: group is already rebalancing (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:10,644] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] (Re-)joining group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:17,720] INFO 172.22.0.7 - - [Tue, 23 Nov 2021 09:20:17 GMT] "GET /info HTTP/2.0" 200 132 "-" "armeria/1.7.2" 0 (io.confluent.ksql.api.server.LoggingHandler)
# [2021-11-23 09:20:41,472] INFO 172.22.0.7 - - [Tue, 23 Nov 2021 09:20:41 GMT] "GET /info HTTP/2.0" 200 132 "-" "armeria/1.7.2" 0 (io.confluent.ksql.api.server.LoggingHandler)
# [2021-11-23 09:20:52,823] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Successfully joined group with generation Generation{generationId=2, memberId='_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer-51a97204-8375-4e9d-a262-9fad0ec08c45', protocol='stream'} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,823] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Successfully joined group with generation Generation{generationId=2, memberId='_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer-69dc8713-9b33-4504-aab2-6231d077794a', protocol='stream'} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,823] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Successfully joined group with generation Generation{generationId=2, memberId='_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer-bbc9b6ee-9144-4268-98d9-68edeaafd2a3', protocol='stream'} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,823] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Successfully joined group with generation Generation{generationId=2, memberId='_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer-f43e90b1-df10-4565-9f17-877e2cf0e981', protocol='stream'} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,827] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer] All members participating in this rebalance: 
# 030e833a-12f2-43b6-a31c-1d8afb59e9a6: [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer-f43e90b1-df10-4565-9f17-877e2cf0e981, _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer-bbc9b6ee-9144-4268-98d9-68edeaafd2a3, _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer-51a97204-8375-4e9d-a262-9fad0ec08c45, _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer-69dc8713-9b33-4504-aab2-6231d077794a]. (org.apache.kafka.streams.processor.internals.StreamsPartitionAssignor)
# [2021-11-23 09:20:52,828] INFO Decided on assignment: {030e833a-12f2-43b6-a31c-1d8afb59e9a6=[activeTasks: ([0_0]) standbyTasks: ([]) prevActiveTasks: ([]) prevStandbyTasks: ([]) changelogOffsetTotalsByTask: ([]) taskLagTotals: ([]) capacity: 4 assigned: 1]} with no followup probing rebalance. (org.apache.kafka.streams.processor.internals.assignment.HighAvailabilityTaskAssignor)
# [2021-11-23 09:20:52,829] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer] Assigned tasks [0_0] including stateful [] to clients as: 
# 030e833a-12f2-43b6-a31c-1d8afb59e9a6=[activeTasks: ([0_0]) standbyTasks: ([])]. (org.apache.kafka.streams.processor.internals.StreamsPartitionAssignor)
# [2021-11-23 09:20:52,830] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer] Client 030e833a-12f2-43b6-a31c-1d8afb59e9a6 per-consumer assignment:
#         prev owned active {}
#         prev owned standby {_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer-f43e90b1-df10-4565-9f17-877e2cf0e981=[], _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer-bbc9b6ee-9144-4268-98d9-68edeaafd2a3=[], _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer-51a97204-8375-4e9d-a262-9fad0ec08c45=[], _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer-69dc8713-9b33-4504-aab2-6231d077794a=[]}
#         assigned active {_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer-f43e90b1-df10-4565-9f17-877e2cf0e981=[0_0]}
#         revoking active {}
#         assigned standby {}
#  (org.apache.kafka.streams.processor.internals.StreamsPartitionAssignor)
# [2021-11-23 09:20:52,830] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer] Finished stable assignment of tasks, no followup rebalances required. (org.apache.kafka.streams.processor.internals.StreamsPartitionAssignor)
# [2021-11-23 09:20:52,830] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Finished assignment for group at generation 2: {_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer-bbc9b6ee-9144-4268-98d9-68edeaafd2a3=Assignment(partitions=[], userDataSize=111), _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer-69dc8713-9b33-4504-aab2-6231d077794a=Assignment(partitions=[], userDataSize=111), _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer-51a97204-8375-4e9d-a262-9fad0ec08c45=Assignment(partitions=[], userDataSize=111), _confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer-f43e90b1-df10-4565-9f17-877e2cf0e981=Assignment(partitions=[SENSORS_RAW-0], userDataSize=123)} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,835] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Successfully synced group in generation Generation{generationId=2, memberId='_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer-bbc9b6ee-9144-4268-98d9-68edeaafd2a3', protocol='stream'} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,835] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Successfully synced group in generation Generation{generationId=2, memberId='_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer-69dc8713-9b33-4504-aab2-6231d077794a', protocol='stream'} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,837] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Successfully synced group in generation Generation{generationId=2, memberId='_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer-f43e90b1-df10-4565-9f17-877e2cf0e981', protocol='stream'} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,837] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Updating assignment with
#         Assigned partitions:                       []
#         Current owned partitions:                  []
#         Added partitions (assigned - owned):       []
#         Revoked partitions (owned - assigned):     []
#  (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,837] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Updating assignment with
#         Assigned partitions:                       []
#         Current owned partitions:                  []
#         Added partitions (assigned - owned):       []
#         Revoked partitions (owned - assigned):     []
#  (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,839] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Notifying assignor about the new Assignment(partitions=[], userDataSize=111) (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,837] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Successfully synced group in generation Generation{generationId=2, memberId='_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer-51a97204-8375-4e9d-a262-9fad0ec08c45', protocol='stream'} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,840] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer] No followup rebalance was requested, resetting the rebalance schedule. (org.apache.kafka.streams.processor.internals.StreamsPartitionAssignor)
# [2021-11-23 09:20:52,840] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Updating assignment with
#         Assigned partitions:                       []
#         Current owned partitions:                  []
#         Added partitions (assigned - owned):       []
#         Revoked partitions (owned - assigned):     []
#  (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,841] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Notifying assignor about the new Assignment(partitions=[], userDataSize=111) (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,839] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Updating assignment with
#         Assigned partitions:                       [SENSORS_RAW-0]
#         Current owned partitions:                  []
#         Added partitions (assigned - owned):       [SENSORS_RAW-0]
#         Revoked partitions (owned - assigned):     []
#  (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,841] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Notifying assignor about the new Assignment(partitions=[SENSORS_RAW-0], userDataSize=123) (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,838] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Notifying assignor about the new Assignment(partitions=[], userDataSize=111) (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,841] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer] No followup rebalance was requested, resetting the rebalance schedule. (org.apache.kafka.streams.processor.internals.StreamsPartitionAssignor)
# [2021-11-23 09:20:52,844] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2] Handle new assignment with:
#         New active tasks: [0_0]
#         New standby tasks: []
#         Existing active tasks: []
#         Existing standby tasks: [] (org.apache.kafka.streams.processor.internals.TaskManager)
# [2021-11-23 09:20:52,843] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer] No followup rebalance was requested, resetting the rebalance schedule. (org.apache.kafka.streams.processor.internals.StreamsPartitionAssignor)
# [2021-11-23 09:20:52,840] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5] Handle new assignment with:
#         New active tasks: []
#         New standby tasks: []
#         Existing active tasks: []
#         Existing standby tasks: [] (org.apache.kafka.streams.processor.internals.TaskManager)
# [2021-11-23 09:20:52,847] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer] No followup rebalance was requested, resetting the rebalance schedule. (org.apache.kafka.streams.processor.internals.StreamsPartitionAssignor)
# [2021-11-23 09:20:52,847] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4] Handle new assignment with:
#         New active tasks: []
#         New standby tasks: []
#         Existing active tasks: []
#         Existing standby tasks: [] (org.apache.kafka.streams.processor.internals.TaskManager)
# [2021-11-23 09:20:52,848] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Adding newly assigned partitions:  (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,848] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4] State transition from RUNNING to PARTITIONS_ASSIGNED (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,848] INFO stream-client [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6] State transition from RUNNING to REBALANCING (org.apache.kafka.streams.KafkaStreams)
# [2021-11-23 09:20:52,848] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3] Handle new assignment with:
#         New active tasks: []
#         New standby tasks: []
#         Existing active tasks: []
#         Existing standby tasks: [] (org.apache.kafka.streams.processor.internals.TaskManager)
# [2021-11-23 09:20:52,847] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Adding newly assigned partitions:  (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,849] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5] State transition from STARTING to PARTITIONS_ASSIGNED (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,848] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Adding newly assigned partitions:  (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,850] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3] State transition from RUNNING to PARTITIONS_ASSIGNED (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,853] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Adding newly assigned partitions: SENSORS_RAW-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,853] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2] State transition from RUNNING to PARTITIONS_ASSIGNED (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,856] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2] task [0_0] Initialized (org.apache.kafka.streams.processor.internals.StreamTask)
# [2021-11-23 09:20:52,857] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Found no committed offset for partition SENSORS_RAW-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,858] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2] task [0_0] Restored and ready to run (org.apache.kafka.streams.processor.internals.StreamTask)
# [2021-11-23 09:20:52,858] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2] Restoration took 5 ms for all tasks [0_0] (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,858] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2] State transition from PARTITIONS_ASSIGNED to RUNNING (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,858] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Requesting the log end offset for SENSORS_RAW-0 in order to compute lag (org.apache.kafka.clients.consumer.KafkaConsumer)
# [2021-11-23 09:20:52,862] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Found no committed offset for partition SENSORS_RAW-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-11-23 09:20:52,862] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4] Restoration took 14 ms for all tasks [] (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,862] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4] State transition from PARTITIONS_ASSIGNED to RUNNING (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,862] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2] Setting topic 'SENSORS_RAW' to consume from latest offset (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,863] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3] Restoration took 13 ms for all tasks [] (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,863] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3] State transition from PARTITIONS_ASSIGNED to RUNNING (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,862] INFO [Consumer clientId=_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2-consumer, groupId=_confluent-ksql-default_query_CSAS_SENSORS_3] Seeking to LATEST offset of partition SENSORS_RAW-0 (org.apache.kafka.clients.consumer.internals.SubscriptionState)
# [2021-11-23 09:20:52,912] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5] Restoration took 63 ms for all tasks [] (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,912] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-5] State transition from PARTITIONS_ASSIGNED to RUNNING (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:20:52,913] INFO stream-client [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6] State transition from REBALANCING to RUNNING (org.apache.kafka.streams.KafkaStreams)
# [2021-11-23 09:21:03,618] INFO 172.22.0.7 - - [Tue, 23 Nov 2021 09:21:03 GMT] "GET /info HTTP/2.0" 200 132 "-" "armeria/1.7.2" 0 (io.confluent.ksql.api.server.LoggingHandler)
# [2021-11-23 09:21:04,732] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-4] Processed 0 total records, ran 0 punctuators, and committed -419 total tasks since the last update (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:21:04,732] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-3] Processed 0 total records, ran 0 punctuators, and committed -419 total tasks since the last update (org.apache.kafka.streams.processor.internals.StreamThread)
# [2021-11-23 09:21:04,732] INFO stream-thread [_confluent-ksql-default_query_CSAS_SENSORS_3-030e833a-12f2-43b6-a31c-1d8afb59e9a6-StreamThread-2] Processed 0 total records, ran 0 punctuators, and committed -419 total tasks since the last update (org.apache.kafka.streams.processor.internals.StreamThread)