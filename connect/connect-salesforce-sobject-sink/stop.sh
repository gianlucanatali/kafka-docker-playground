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

    # second account (for Bulk API sink)
    SALESFORCE_USERNAME_ACCOUNT2=${SALESFORCE_USERNAME_ACCOUNT2:-$6}
    SALESFORCE_PASSWORD_ACCOUNT2=${SALESFORCE_PASSWORD_ACCOUNT2:-$7}
    SECURITY_TOKEN_ACCOUNT2=${SECURITY_TOKEN_ACCOUNT2:-$8}
    SALESFORCE_INSTANCE_ACCOUNT2=${SALESFORCE_INSTANCE_ACCOUNT2:-"https://login.salesforce.com"}

    log "Login with sfdx CLI on the account #2"
    docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SECURITY_TOKEN_ACCOUNT2\""

    log "Bulk delete leads"
    docker exec sfdx-cli sh -c "sfdx force:data:soql:query -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -q \"SELECT Id FROM Lead\" --resultformat csv" > /tmp/out.csv
    docker cp /tmp/out.csv sfdx-cli:/tmp/out.csv
    docker exec  sfdx-cli sh -c "sfdx force:data:bulk:delete -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -s Lead -f /tmp/out.csv"
fi

stop_all "$DIR"