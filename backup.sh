#!/bin/bash

source /log.sh

#Catch errors
err=0
trap '((err+=1))' ERR

source environment.sh

THIS_CONTAINER=$(cat /etc/hostname)
THIS_IMAGE=$(docker container inspect $THIS_CONTAINER | jq -r '.[0].Config.Image')
CONTAINERS=$(docker container ls -aqf "label=$BACKUP_LABEL.volumes")
SAVED_VOLUMES=""

mkdir -p $BACKUP_DIR

if [[ "$CONTAINERS" == "" ]]; then
  log info "No containers to backup!"
  exit 0
fi

for CONTAINER in $CONTAINERS; do
  NAME=$(docker container inspect $CONTAINER | jq -r '.[0].Name')
  
  log info "Processing container $NAME..."
  
  PROJECT=$(docker container inspect $CONTAINER | jq -r '.[0].Config.Labels."com.docker.compose.project"')     
  RUNNING=$(docker container inspect $CONTAINER | jq -r '.[0].State.Running')
  VOLUMES=$(docker container inspect $CONTAINER | jq -r ".[0].Config.Labels.\"$BACKUP_LABEL.volumes\"")
  STOP=$(docker container inspect $CONTAINER | jq -r ".[0].Config.Labels.\"$BACKUP_LABEL.stop\"")
  PRE_CMD=$(docker container inspect $CONTAINER | jq -r ".[0].Config.Labels.\"$BACKUP_LABEL.pre\"")
  POST_CMD=$(docker container inspect $CONTAINER | jq -r ".[0].Config.Labels.\"$BACKUP_LABEL.post\"")

  [[ "$PRE_CMD" != "null" ]] && echo "Running Pre CMD: $PRE_CMD"
  [[ "$PRE_CMD" != "null" ]] && eval "docker exec $CONTAINER $PRE_CMD"

  [[ "$RUNNING" == "true" ]] && [[ "$STOP" != "null" ]] && log info "Stopping container $NAME..." && docker stop $CONTAINER > /dev/null

  for VOLUME in $VOLUMES; do
    SOURCE="$(docker volume inspect "${PROJECT}_${VOLUME}" | jq -r '.[0].Mountpoint')"
    DEST="${PROJECT}_${VOLUME}.tar.gz"

    log info "Compressing $DEST..."
    docker run --rm --volume "${PROJECT}_${VOLUME}:/containervolume:ro" --volumes-from "$THIS_CONTAINER" --entrypoint "" $THIS_IMAGE tar -czf "$BACKUP_DIR/$DEST" --directory='/containervolume' .

    SAVED_VOLUMES+=" ${PROJECT}_${VOLUME}"
  done

  [[ "$RUNNING" == "true" ]] && [[ "$STOP" != "null" ]] && log info "Restarting container $NAME..." && docker start $CONTAINER > /dev/null

  [[ "$POST_CMD" != "null" ]] && echo "Running Post CMD: $POST_CMD"
  [[ "$POST_CMD" != "null" ]] && eval "docker exec $CONTAINER $POST_CMD"
  
done

# BACKUP TO GCP
[[ -n "$GS_SA_KEY" ]] && echo "$GS_SA_KEY" | base64 -d | gcloud --no-user-output-enabled auth activate-service-account --key-file=-
[[ -n "$GS_BUCKET_NAME" ]] && log info "Uploading archives to GCP bucket: $GS_BUCKET_NAME"
[[ -n "$GS_BUCKET_NAME" ]] && gsutil -q cp "$BACKUP_DIR/*.tar.gz" "gs://$GS_BUCKET_NAME"

# BACKUP TO S3
[[ -n "$AWS_BUCKET_NAME" ]] && log info "Uploading archives to S3 bucket: $AWS_BUCKET_NAME"
[[ -n "$AWS_BUCKET_NAME" ]] && aws s3 cp --only-show-errors "$BACKUP_DIR/*.tar.gz" "s3://$AWS_BUCKET_NAME"

log info "Removing backup archives..."
rm "$BACKUP_DIR/"*.tar.gz

[[ -n "$HEALTHCHECK_UUID" ]] && log info "Reporting to healthchecks.io id: $HEALTHCHECK_UUID..."
[[ -n "$HEALTHCHECK_UUID" ]] && curl -s -m 10 --retry 5 "https://hc-ping.com/$HEALTHCHECK_UUID/$err" > /dev/null

log info "Saved volumes: $SAVED_VOLUMES"
log info "Completed with $err errors"
exit $err
