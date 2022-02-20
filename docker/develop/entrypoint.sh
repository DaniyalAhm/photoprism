#!/usr/bin/env bash

DOCKER_ARCH=${DOCKER_ARCH:-arch}
DOCKER_ENV=${DOCKER_ENV:-unknown}
DOCKER_TAG=${DOCKER_TAG:-unknown}

echo "image: $DOCKER_ARCH-$DOCKER_ENV (build $DOCKER_TAG)"

if [[ $(id -u) == "0" ]]; then
  echo "started as root"

  if [[ ! -e /root/.init ]] && [[ ${PHOTOPRISM_INIT} ]]; then
    for target in $PHOTOPRISM_INIT; do
      echo "init ${target}..."
      make -f /go/src/github.com/photoprism/photoprism/scripts/dist/Makefile "${target}"
    done
    echo 1 >/root/.init
  fi
else
  echo "started as uid $(id -u)"
fi

re='^[0-9]+$'

# check for alternate umask variable
if [[ -z ${PHOTOPRISM_UMASK} ]] && [[ ${UMASK} =~ $re ]] && [[ ${#UMASK} == 4 ]]; then
  PHOTOPRISM_UMASK=${UMASK}
fi

# set file-creation mode (umask)
if [[ ${PHOTOPRISM_UMASK} =~ $re ]] && [[ ${#PHOTOPRISM_UMASK} == 4 ]]; then
  umask "${PHOTOPRISM_UMASK}"
else
  umask 0002
fi

echo "umask: \"$(umask)\" ($(umask -S))"

# script must run as root to perform changes
if [[ $(id -u) == "0" ]]; then
  # check for alternate user ID env variables
  if [[ -z ${PHOTOPRISM_UID} ]]; then
    if [[ ${UID} =~ $re ]] && [[ ${UID} != "0" ]]; then
      PHOTOPRISM_UID=${UID}
    elif [[ ${PUID} =~ $re ]] && [[ ${PUID} != "0" ]]; then
      PHOTOPRISM_UID=${PUID}
    fi
  fi

  # check for alternate group ID env variables
  if [[ -z ${PHOTOPRISM_GID} ]]; then
    if [[ ${GID} =~ $re ]] && [[ ${GID} != "0" ]]; then
      PHOTOPRISM_GID=${GID}
    elif [[ ${PGID} =~ $re ]] && [[ ${PGID} != "0" ]]; then
      PHOTOPRISM_GID=${PGID}
    fi
  fi

  # check uid and gid env variables
  if [[ ${PHOTOPRISM_UID} =~ $re ]] && [[ ${PHOTOPRISM_UID} != "0" ]] && [[ ${PHOTOPRISM_GID} =~ $re ]] && [[ ${PHOTOPRISM_GID} != "0" ]]; then
    # RUN AS SPECIFIED USER + GROUP ID
    groupadd -g "${PHOTOPRISM_GID}" "group_${PHOTOPRISM_GID}" 2>/dev/null
    useradd -o -u "${PHOTOPRISM_UID}" -g "${PHOTOPRISM_GID}" -d /photoprism "user_${PHOTOPRISM_UID}" 2>/dev/null
    usermod -g "${PHOTOPRISM_GID}" "user_${PHOTOPRISM_UID}" 2>/dev/null

    if [[ -z ${PHOTOPRISM_DISABLE_CHOWN} ]]; then
      echo "updating storage permissions..."
      chown --preserve-root -Rcf "${PHOTOPRISM_UID}:${PHOTOPRISM_GID}" /go /photoprism /opt/photoprism /tmp/photoprism
      chmod --preserve-root -Rcf u+rwX /go/src/github.com/photoprism/photoprism/* /photoprism /opt/photoprism /tmp/photoprism
      echo "PHOTOPRISM_DISABLE_CHOWN: \"true\" disables storage permission updates"
    fi

    echo "switching to uid ${PHOTOPRISM_UID}:${PHOTOPRISM_GID}"
    echo "${@}"

    gosu "${PHOTOPRISM_UID}:${PHOTOPRISM_GID}" "$@" &
  elif [[ ${PHOTOPRISM_UID} =~ $re ]] && [[ ${PHOTOPRISM_UID} != "0" ]]; then
    # RUN AS SPECIFIED USER ID
    useradd -o -u "${PHOTOPRISM_UID}" -g 1000 -d /photoprism "user_${PHOTOPRISM_UID}" 2>/dev/null
    usermod -g 1000 "user_${PHOTOPRISM_UID}" 2>/dev/null

    if [[ -z ${PHOTOPRISM_DISABLE_CHOWN} ]]; then
      echo "updating storage permissions..."
      chown --preserve-root -Rcf "${PHOTOPRISM_UID}" /go /photoprism /opt/photoprism /tmp/photoprism
      chmod --preserve-root -Rcf u+rwX /go/src/github.com/photoprism/photoprism/* /photoprism /opt/photoprism /tmp/photoprism
      echo "PHOTOPRISM_DISABLE_CHOWN: \"true\" disables storage permission updates"
    fi

    echo "switching to uid ${PHOTOPRISM_UID}"
    echo "${@}"

    gosu "${PHOTOPRISM_UID}" "$@" &
  else
    # RUN AS ROOT
    echo "running as root"
    echo "${@}"

    "$@" &
  fi
else
  # RUN AS NON-ROOT USER
  echo "running as uid $(id -u)"
  echo "${@}"

  "$@" &
fi

PID=$!

trap "kill $PID" INT TERM
wait
