#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-92035-http-sink-connector-and-redirects.yml"


log "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

log "-------------------------------------"
log "Running Simple (No) Authentication Example"
log "-------------------------------------"

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-no-auth-307:8080/redirect"
          }' \
     http://localhost:8083/connectors/http-sink-307/config | jq .

sleep 10

# 2022-02-10 21:14:20,796] ERROR [http-sink-307|task-0] WorkerSinkTask{id=http-sink-307-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://http-service-no-auth-307:8080/redirect, Status code : 307, Reason Phrase : , Response Content : , 
#         at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:399)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:282)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:179)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
# Caused by: Error while processing HTTP request with Url : http://http-service-no-auth-307:8080/redirect, Status code : 307, Reason Phrase : , Response Content : , 
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:370)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:303)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:277)
#         ... 13 more


log "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log

timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 1

# curl -L -vvv -X POST http://localhost:8080/redirect --data 'test'
# Note: Unnecessary use of -X or --request, POST is already inferred.
# *   Trying ::1:8080...
# * Connected to localhost (::1) port 8080 (#0)
# > POST /redirect HTTP/1.1
# > Host: localhost:8080
# > User-Agent: curl/7.77.0
# > Accept: */*
# > Content-Length: 4
# > Content-Type: application/x-www-form-urlencoded
# > 
# * Mark bundle as not supporting multiuse
# < HTTP/1.1 307 
# < Location: /api/messages
# < X-Content-Type-Options: nosniff
# < X-XSS-Protection: 1; mode=block
# < Cache-Control: no-cache, no-store, max-age=0, must-revalidate
# < Pragma: no-cache
# < Expires: 0
# < X-Frame-Options: DENY
# < Content-Language: en-US
# < Content-Length: 0
# < Date: Thu, 10 Feb 2022 21:13:38 GMT
# < 
# * Connection #0 to host localhost left intact
# * Issue another request to this URL: 'http://localhost:8080/api/messages'
# * Found bundle for host localhost: 0x60000138cde0 [serially]
# * Can not multiplex, even if we wanted to!
# * Re-using existing connection! (#0) with host localhost
# * Connected to localhost (::1) port 8080 (#0)
# > POST /api/messages HTTP/1.1
# > Host: localhost:8080
# > User-Agent: curl/7.77.0
# > Accept: */*
# > Content-Length: 4
# > Content-Type: application/x-www-form-urlencoded
# > 
# * Mark bundle as not supporting multiuse
# < HTTP/1.1 201 
# < X-Content-Type-Options: nosniff
# < X-XSS-Protection: 1; mode=block
# < Cache-Control: no-cache, no-store, max-age=0, must-revalidate
# < Pragma: no-cache
# < Expires: 0
# < X-Frame-Options: DENY
# < Content-Type: application/json;charset=UTF-8
# < Transfer-Encoding: chunked
# < Date: Thu, 10 Feb 2022 21:13:38 GMT
# < 
# * Connection #0 to host localhost left intact
# {"id":2,"message":"test="}%    