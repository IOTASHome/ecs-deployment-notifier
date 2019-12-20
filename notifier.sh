#!/bin/bash
# sensitive data is passed into the script as a deployment varibles (Slack hooks)

#argument definitions
ENV_NAME=$1
TARGET_REVISION=$2
VERSION_ID=$3
#slack message definition
SLACK_PAYLOAD="*$ENV_NAME environment* deployment of \`$VERSION_ID\` is now live"
#cluster definition
CLUSTER_NAME="$ENV_NAME-ENTER-YOUR-CLUSTER-NAME"

#region setup
if [ $ENV_NAME = 'dev' ] || [ $ENV_NAME = 'staging' ] || [ $ENV_NAME = 'dfe' ]; then
    REGION='us-west-2'
    SLACK_HOOK_URL=$NON_PROD_SLACK_HOOK_URL
elif [ $ENV_NAME = 'prod' ]; then
    REGION='us-east-1'
    SLACK_HOOK_URL=$PROD_SLACK_HOOK_URL
else
    echo 'invalid environment'
    exit 1
fi

#handle errors by restarting script
function errorHandler() {
    if [ "$?" = "1" ]; then
        echo "Error caught!"
        sleep 15
        echo "Restarting Script"
        exec "$0" "$ENV_NAME" "$TARGET_REVISION" "$VERSION_ID"
    fi
}
#grab ECS task data
function setBaseVars() {
    ALL_TASK_DATA=$(aws ecs list-tasks --region $REGION --cluster $CLUSTER_NAME)
    NUM_TASKS=$(echo "$ALL_TASK_DATA" | jq '.[] | length')
}
#compare current data on all tasks against desired target revision
function compareRevisions() {
    ARRAY_COUNT=0
    UPDATE_COMPLETE=true
    while [ $ARRAY_COUNT -lt $NUM_TASKS ]; do
        TASK_SHORT_ARN=$(echo "$ALL_TASK_DATA" | jq -r '.taskArns['$ARRAY_COUNT']' | sed 's#^[^/]*/##g')
        errorHandler
        TASK_DATA=$(aws ecs describe-tasks --region $REGION --cluster $CLUSTER_NAME --tasks $TASK_SHORT_ARN)
        errorHandler
        TASK_REVISION=$(echo "$TASK_DATA" | jq '.tasks' | jq '.[]' | jq -r '.taskDefinitionArn' | grep -Eo '[0-9]+$')
        errorHandler
        echo "Task $(($ARRAY_COUNT + 1)) Short ARN: $TASK_SHORT_ARN"
        echo "Task $(($ARRAY_COUNT + 1)) Revision: $TASK_REVISION"
        let ARRAY_COUNT=ARRAY_COUNT+1
        if [ "$TASK_REVISION" -ne "$TARGET_REVISION" ]; then
            UPDATE_COMPLETE=false
        fi
    done
    if [ "$UPDATE_COMPLETE" = true ]; then
        slack
    else
        echo "Not Updated!"
        sleep 15
        echo "Restarting Script"
        exec "$0" "$ENV_NAME" "$TARGET_REVISION" "$VERSION_ID"
    fi
}
#post to slack
function slack() {
    curl -X POST -H 'Content-type: application/json' --data '{"text":"'"$SLACK_PAYLOAD"'"}' $SLACK_HOOK_URL
}

setBaseVars
echo "Environment: $ENV_NAME"
echo "Number of tasks: $NUM_TASKS"
compareRevisions
