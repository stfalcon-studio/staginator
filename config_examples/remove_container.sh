#!/bin/bash

# remove_container.sh <project_name> <branch_name>

PROJECT_NAME=$1
BRANCH_NAME=$2

docker stop $PROJECT_NAME-staging-$BRANCH_NAME
docker rm $PROJECT_NAME-staging-$BRANCH_NAME

rm /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf
/etc/init.d/nginx reload

#echo "staging from branch: $BRANCH_NAME removed" | slackcmd.py -u [slack_webhook_url] -c "#$PROJECT_NAME" -n Staginator
