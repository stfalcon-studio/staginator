#!/bin/bash

# create_new_container <project_name> <branch_name>

PROJECT_NAME=$1
BRANCH_NAME=$2
SHARED_DATA=/usr/share/stagings/$PROJECT_NAME

if [ ! -d "$SHARED_DATA" ]; then
  mkdir $SHARED_DATA
  mkdir $SHARED_DATA/composer_cache
fi

docker stop $PROJECT_NAME-staging-$BRANCH_NAME
docker rm $PROJECT_NAME-staging-$BRANCH_NAME

docker run -d --link $PROJECT_NAME-mysql:$PROJECT_NAME-mysql -v $SHARED_DATA:/stag/shared -e STAGING_BRANCH=$BRANCH_NAME --name $PROJECT_NAME-staging-$BRANCH_NAME --hostname=$PROJECT_NAME-staging-$BRANCH_NAME $PROJECT_NAME-staging

CONT_IP=`docker inspect $PROJECT_NAME-staging-$BRANCH_NAME|grep IPAddress| awk '{print $2}'|cut -f2 -d '"'`

cp /etc/nginx-staging-template.conf /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf

sed -i s/%BRANCH%/$BRANCH_NAME/ /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf
sed -i s/%PROJECT%/$PROJECT_NAME/ /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf
sed -i s/%CONT_IP%/$CONT_IP/ /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf

/etc/init.d/nginx reload
