#!/usb/bin/env bash
set -e

log() {
  echo ">> [local]" $@
}

cleanup() {
  set +e
  log "Killing ssh agent."
  ssh-agent -k

  if ! $NO_BUILD
  then
    log "Removing workspace archive."
    rm -f /tmp/workspace.tar.bz2
  fi
}
trap cleanup EXIT

log "Packing workspace into archive to transfer onto remote machine."
tar cjvf /tmp/workspace.tar.bz2 --exclude .git .

log "Launching ssh agent."
eval `ssh-agent -s`

ssh-add <(echo "$SSH_PRIVATE_KEY" | base64 -d)

remote_command="set -e; 

log() { 
    echo '>> [remote]' \$@ ; 
}; 

workdir=\"\$HOME/${DOCKER_COMPOSE_PREFIX}_workspace\"

if [ -d \$workdir ] 
then
    if [ -f \$workdir/$DOCKER_COMPOSE_FILENAME ] 
    then
      log 'Docker Compose Down...'; 
      docker-compose -f \$workdir/$DOCKER_COMPOSE_FILENAME down
    fi
    log 'Removing workspace...'; 
    rm -rf \$workdir; 
fi

log 'Creating workspace directory...';
mkdir \$workdir; 

log 'Unpacking workspace...'; 
tar -C \$workdir -xjv; 

if ! $NO_BUILD
then
  log 'Launching docker-compose...'; 
  cd \$workdir; 

  if $NO_CACHE
  then
    docker-compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" build --no-cache 
    docker-compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" up -d --remove-orphans --force-recreate
  else 
    docker-compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" up -d --remove-orphans --build;
  fi
fi"

echo ">> [local] Connecting to remote host."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$SSH_USER@$SSH_HOST" -p "$SSH_PORT" \
  "$remote_command" \
  < /tmp/workspace.tar.bz2
