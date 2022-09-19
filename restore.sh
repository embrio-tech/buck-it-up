#!/bin/bash

source /log.sh

#Catch errors
err=0
trap '((err+=1))' ERR

source environment.sh

THIS_CONTAINER=$(cat /etc/hostname)
THIS_IMAGE=$(docker container inspect $THIS_CONTAINER | jq -r '.[0].Config.Image')

RESTORE_PROJECTS="$@"
RESTORED_VOLUMES=""
CONTAINERS=""

if [[ "$RESTORE_PROJECTS" == "ALL" ]]; then
  log info "Restoring ALL Projects..."
  CONTAINERS=$(docker container ls -aq -f "label=$BACKUP_LABEL.volumes")
  else
  for PROJECT in $RESTORE_PROJECTS; do
  log info "Restoring $PROJECT..."
  CONTAINERS+=" $(docker container ls -aq -f label=$BACKUP_LABEL.volumes -f label=com.docker.compose.project=$PROJECT)"
  done
fi

if [[ "$CONTAINERS" == "" ]]; then
  log info "No containers to restore!"
  exit 0
fi

read -p "Are you sure to continue? (THIS CAN NOT BE UNDONE!) [y/N]" -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

[[ -n "$GS_SA_KEY" ]] && echo "$GS_SA_KEY" | base64 -d | gcloud --no-user-output-enabled auth activate-service-account --key-file=-

for CONTAINER in $CONTAINERS; do
  NAME=$(docker container inspect $CONTAINER | jq -r '.[0].Name')
  
  log info "Processing container $NAME..."
  
  PROJECT=$(docker container inspect $CONTAINER | jq -r '.[0].Config.Labels."com.docker.compose.project"')     
  RUNNING=$(docker container inspect $CONTAINER | jq -r '.[0].State.Running')
  VOLUMES=$(docker container inspect $CONTAINER | jq -r ".[0].Config.Labels.\"$BACKUP_LABEL.volumes\"")
  RESTORE_CMD=$(docker container inspect $CONTAINER | jq -r ".[0].Config.Labels.\"$BACKUP_LABEL.restore\"")

  [[ -n "$GS_BUCKET_NAME" ]] && log info "Retrieving archives from GCP bucket: $GS_BUCKET_NAME"
  for VOLUME in $VOLUMES; do
    [[ -n "$GS_BUCKET_NAME" ]] && gsutil -q cp "gs://$GS_BUCKET_NAME/${PROJECT}_${VOLUME}.tar.gz" "$BACKUP_DIR/"
  done

  [[ "$RUNNING" == "true" ]] && log info "Stopping container $NAME..." && docker stop $CONTAINER > /dev/null

  for VOLUME in $VOLUMES; do
    SOURCE="/$BACKUP_DIR/${PROJECT}_${VOLUME}.tar.gz"
    log info "Restoring volume: ${PROJECT}_${VOLUME}"
    docker run --rm --volume "${PROJECT}_${VOLUME}:/containervolume" --volumes-from "$THIS_CONTAINER" --entrypoint "" $THIS_IMAGE rm -rf /containervolume/*
    docker run --rm --volume "${PROJECT}_${VOLUME}:/containervolume" --volumes-from "$THIS_CONTAINER" --entrypoint "" $THIS_IMAGE tar -xzf "$SOURCE" --directory='/containervolume'

    RESTORED_VOLUMES+=" $VOLUME"
  done

  [[ "$RUNNING" == "true" ]] && log info "Restarting container $NAME..." && docker start $CONTAINER > /dev/null

  if [[ "$RESTORE_CMD" != "null" ]]; then
    [[ "$RUNNING" == "false" ]] && log info "Starting container $NAME..." && docker start $CONTAINER > /dev/null
    sleep 10;
    until [ "$(docker inspect -f {{.State.Running}} $CONTAINER)" == "true" ]; do
      sleep 5;
      log info "Waiting for container $NAME..."
    done;
    echo "Running Pre CMD: $RESTORE_CMD"
    eval "docker exec $CONTAINER $RESTORE_CMD"
  fi
  
done

log info "Restored volumes: $RESTORED_VOLUMES"
log info "Removing restore archives..."
rm "$BACKUP_DIR/"*.tar.gz

log info "Completed with $err errors"
exit $err
