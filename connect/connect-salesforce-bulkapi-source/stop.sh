#!/bin/bash



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


    SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
    SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
    SECURITY_TOKEN=${SECURITY_TOKEN:-$5}
    SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}

    log "Login with sfdx CLI on the account #2"
    docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SECURITY_TOKEN\""

    log "Bulk delete leads"
    docker exec sfdx-cli sh -c "sfdx force:data:soql:query -u \"$SALESFORCE_USERNAME\" -q \"SELECT Id FROM Lead\" --resultformat csv" > /tmp/out.csv
    docker cp /tmp/out.csv sfdx-cli:/tmp/out.csv
    docker exec  sfdx-cli sh -c "sfdx force:data:bulk:delete -u \"$SALESFORCE_USERNAME\" -s Lead -f /tmp/out.csv"
fi

stop_all "$DIR"