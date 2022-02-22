package com.github.vdesabou;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.config.SaslConfigs;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import java.util.Properties;
import java.util.concurrent.TimeUnit;
import com.github.vdesabou.Customer;
import java.util.Date;

public class SimpleProducer {

    private static final String TOPIC = "customer";

    public static void main(String[] args) throws InterruptedException {


        Properties props = new Properties();

        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, System.getenv("BOOTSTRAP_SERVERS"));

        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 20000);
        props.put(ProducerConfig.RETRY_BACKOFF_MS_CONFIG, 500);
        props.put(ProducerConfig.RETRIES_CONFIG, Integer.MAX_VALUE);

        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class);

        // Schema Registry specific settings
        props.put("schema.registry.url", System.getenv("SCHEMA_REGISTRY_URL"));


        System.out.println("Sending data to `customer` topic. Properties: " + props.toString());

        try (Producer<String, Customer> producer = new KafkaProducer<>(props)) {
            long i = 0;

            while (true) {
                String key = "" + i;

                ProducerRecord<String, Customer> record;
                Customer customer = Customer.newBuilder()
                .setF1(1)
                .setF2(null)
                .setF3(3)
                .build();
                record = new ProducerRecord<>(TOPIC, key, customer);

                System.out.println("Sending " + record.key() + " " + record.value());
                producer.send(record, new Callback() {
                    @Override
                    public void onCompletion(RecordMetadata metadata, Exception exception) {
                        if (exception == null) {
                            System.out.printf("Produced record to topic %s partition [%d] @ offset %d%n", metadata.topic(), metadata.partition(), metadata.offset());
                        } else {
                            exception.printStackTrace();
                        }
                    }
                });
                producer.flush();
                i++;
                TimeUnit.MILLISECONDS.sleep(5000);
            }
        }
    }
}
