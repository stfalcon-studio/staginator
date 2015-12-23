#!/bin/bash

# create_new_container <project_name> <branch_name>

PROJECT_NAME=$1
BRANCH_NAME=$2
MEMORY_LIMIT=$3
CPU_CORES=$4
SHARED_DATA=/usr/share/stagings/$PROJECT_NAME
MYSQL_CONTAINER=`docker ps |grep $PROJECT_NAME-mysql`

if [ ! -d "$SHARED_DATA" ]; then
  mkdir $SHARED_DATA
  mkdir $SHARED_DATA/composer_cache
fi

docker stop $PROJECT_NAME-staging-$BRANCH_NAME
docker rm $PROJECT_NAME-staging-$BRANCH_NAME
if [ -z "$MYSQL_CONTAINER" ]; then
        docker run -d -m $MEMORY_LIMIT --cpuset="$CPU_CORES" -v $SHARED_DATA:/stag/shared -e STAGING_BRANCH=$BRANCH_NAME --name $PROJECT_NAME-staging-$BRANCH_NAME --hostname=$BRANCH_NAME $PROJECT_NAME-staging
else
        docker run -d -m $MEMORY_LIMIT --cpuset="$CPU_CORES" --link $PROJECT_NAME-mysql:$PROJECT_NAME-mysql -v $SHARED_DATA:/stag/shared -e STAGING_BRANCH=$BRANCH_NAME --name $PROJECT_NAME-staging-$BRANCH_NAME --hostname=$BRANCH_NAME $PROJECT_NAME-staging

fi

CONT_IP=`docker inspect $PROJECT_NAME-staging-$BRANCH_NAME|grep \"IPAddress| awk '{print $2}'|cut -f2 -d '"'|head -n1`

cp /etc/nginx-staging-template.conf /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf

sed -i s/%BRANCH%/$BRANCH_NAME/ /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf
sed -i s/%PROJECT%/$PROJECT_NAME/ /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf
sed -i s/%CONT_IP%/$CONT_IP/ /etc/nginx/conf.d/$PROJECT_NAME-staging-$BRANCH_NAME\.conf

/etc/init.d/nginx reload

#/usr/local/bin/generate_links.py $PROJECT_NAME

echo "new staging from branch: $BRANCH_NAME in progress. Logs: http://$BRANCH_NAME.$PROJECT_NAME.stag.stfalcon.com " | slackcmd.py -u https://hooks.slack.com/services/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 -c "#$PROJECT_NAME" -n Terminator
