#!/bin/bash

set -o nounset \
    -o errexit \
    -o verbose

# See what is in each keystore and truststore
for i in restproxy $CCLOUD_REST_PROXY_SECURITY_PLUGIN_API_KEY
do
        echo "------------------------------- $i keystore -------------------------------"
        keytool -list -v -keystore /tmp/kafka.$i.keystore.jks -storepass confluent | grep -e Alias -e Entry
        echo "------------------------------- $i truststore -------------------------------"
        keytool -list -v -keystore /tmp/kafka.$i.truststore.jks -storepass confluent | grep -e Alias -e Entry
done
