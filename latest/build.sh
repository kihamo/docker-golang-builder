#!/bin/sh

set -e
#if [ -n "$BASH" ]; then
#  set -o pipefaili
#fi

export GOOS=linux
export CGO_ENABLED=0

RETURN_CODE_SUCCESS=0
RETURN_CODE_MAIN_NOT_FOUND=101
RETURN_CODE_BUILD_FAILED=102

DEBUG=0
DEPS_LOADED=0

GO_SOURCE_DIR="/src"
GO_SOURCE_PATH=$GOPATH"/src/"

GO_PACKAGE_COMPRESS=0
GO_BUILD_LDFLAGS="-s"
GO_BUILD_FLASG="-a -tags netgo -installsuffix netgo"

GLIDE_FILE="glide.yaml"
DEP_FILE="Gopkg.toml"
VGO_FILE="go.mod"

DOCKER_IMAGE_PREFIX=""
DOCKER_IMAGE_TAG="latest"

# colors
CL_RESET="\033[0m"
CL_RED="\033[31m"
CL_GREEN="\033[32m"
CL_YELLOW="\033[33m"

# Update packages
# $1 [string] main package import path
# $2 [string] go path
do_go_get() {
  if [ $DEPS_LOADED -eq 1 ]; then
    log_msg "debug" "Dependencies already loaded."
    return $RETURN_CODE_SUCCESS
  fi

  cd ${2}${1}

  if [ -e "$VGO_FILE" ]; then
      log_msg "debug" "Find Golang VGO in $1"

      if [ $DEBUG -eq 0 ]; then
        vgo mod -vendor
      else
        vgo mod -vendor -v
      fi
  elif [ -e "$DEP_FILE" ]; then
      log_msg "debug" "Find Golang dep in $1"

      if [ $DEBUG -eq 0 ]; then
        dep ensure
      else
        dep ensure -v
      fi
  elif [ -e "$GLIDE_FILE" ]; then
      log_msg "debug" "Find Glide in $1"

      if [ $DEBUG -eq 0 ]; then
        glide -y $GLIDE_FILE install
      else
        glide -y $GLIDE_FILE --debug install
      fi
  elif [ -e "Godeps/_workspace" ]; then
    log_msg "debug" "Find Godep in $1"

    if [ `find Godeps/_workspace/src -mindepth 1 -type d | wc -l` -eq 0 ]; then
      if [ $DEBUG -eq 0 ]; then
        godep restore
      else
        godep restore -v
      fi

    else
      export GOPATH=$2/src/$1/Godeps/_workspace:$GOPATH
      export PATH=$2/src/$1/Godeps/_workspace/bin:$PATH
    fi
  else
    log_msg "debug" "Package manager not found"

    if [ $DEBUG -eq 0 ]; then
      go get -t -d ./...
    else
      go get -t -d -v ./...
    fi
  fi

  DEPS_LOADED=1
  return $RETURN_CODE_SUCCESS
}

# Build binary
# $1 [string]  package import path
# $2 [string]  go path
# $3 [string]  build flags
# $4 [boolean] compress binary
do_go_build() {
  log_msg "info" "Build Go package $1"

  cd ${2}${1}

  if [ `go list -e -f '{{.Name}}' 2>/dev/null || true` != "main" ]; then
    log_msg "fatal" "Ignore build package $1. Not found main package"
    return $RETURN_CODE_MAIN_NOT_FOUND
  fi

  go clean

  if [ -e "./Makefile" ]; then
    set +e
    make build-pre
    make build
    set -e
  fi

  if [ ! -e "./Makefile" ] || [ $? -ne 0 ]; then
    if [ $DEBUG -eq 0 ]; then
      go build $GO_BUILD_FLASG -ldflags "$3" .
    else
      go build -v $GO_BUILD_FLASG -ldflags "$3" .
    fi
  fi

  if [ $? -eq 0 ]; then
    if [ $4 -eq 1 ]; then
      goupx --strip-binary ${1##*/}
    fi

    if [ -e "./Makefile" ]; then
      set +e
      make build-post
      set -e
    fi
  else
    log_msg "fatal" "Build package $1 FAILED"
    return $RETURN_CODE_BUILD_FAILED
  fi

  log_msg "info" "Build Go package $1 SUCCESS"
  return $RETURN_CODE_SUCCESS
}

# Build docker image
# $1 [string] package import path
# $2 [string] go path
# $3 [string] image name
# $4 [string] image version
do_docker_build() {
  if ! [ -S "/var/run/docker.sock" ]; then
    log_msg "warn" "Docker socket not found in package $1"
    return $RETURN_CODE_SUCCESS
  fi

  cd ${2}${1}

  if ! [ -s "./Dockerfile" ]; then
    log_msg "warn" "Dockerfile socket not found in package $1"
    return $RETURN_CODE_SUCCESS
  fi

  log_msg "info" "Build Docker image $3 for package $1"

  if [ $DEBUG -eq 0 ]; then
    docker build -q -t $3":"$4 ./
  else
    docker build -t $3":"$4 ./
  fi

  log_msg "info" "Build Docker image $3 for package $1 SUCCESS"
  return $RETURN_CODE_SUCCESS
}

# Release package
# $1 [string] package import path
# $2 [string] go path
# $3 [string] docker image name
# $4 [string] docker image tag
do_release() {
  cd ${2}${1}

  # package main not found
  if [ `go list -e -f '{{.Name}}' 2>/dev/null || true` != "main" ]; then
    log_msg "info" "Ignore build package $1. Not found main package"
    return $RETURN_CODE_SUCCESS
  fi

  set +e
  do_go_get "$1" "$2"
  RETURN_CODE=$?
  set -e
  if [ $RETURN_CODE -ne 0 ]; then
    log_msg "fatal" "Execute do_go_get for package $1 FAILED"
    return $RETURN_CODE
  fi

  set +e
  do_go_build "$1" "$2" "$GO_BUILD_LDFLAGS" $GO_PACKAGE_COMPRESS
  STATUS_CODE=$?
  set -e
  if [ $RETURN_CODE -ne 0 ]; then
    log_msg "fatal" "Execute do_go_build for package $1 FAILED"
    return $RETURN_CODE
  fi

  set +e
  do_docker_build "$1" "$2" $3 $4
  RETURN_CODE=$?
  set -e

  if [ $RETURN_CODE -ne 0 ]; then
    log_msg "fatal" "Execute do_docker_build for package $1 FAILED"
    return $RETURN_CODE
  fi

  return $RETURN_CODE_SUCCESS
}

# Log
# $1 [integer] log level
# $2 [string] message
log_msg() {
    case $1 in
      "panic")
         shift
         echo "${CL_RED}[PANIC]${CL_RESET} $@" >&2
         echo "$USAGE"
         ;;
      "fatal")
         shift
         echo "${CL_RED}[FATAL]${CL_RESET} $@" >&2
         echo "$USAGE"
         ;;
      "error")
         shift
         echo "${CL_RED}[ERROR]${CL_RESET} $@" >&2
         echo "$USAGE"
         ;;
      "warn")
         shift
         echo "${CL_YELLOW}[WARN]${CL_RESET} $@"
         ;;
      "info")
         shift
         echo "${CL_GREEN}[INFO]${CL_RESET} $@"
         ;;
      *)
         if [ "$DEBUG" = 1 ]; then
          shift
          echo "[DEBUG] $@"
         fi
         ;;
    esac
}

OPTSPEC=":-:"
while getopts "$OPTSPEC" OPT; do
  case $OPT in
        -)
            case "$OPTARG" in
                compress)
                    GO_PACKAGE_COMPRESS=1
                    ;;
                flags)
                    GO_BUILD_LDFLAGS="$GO_BUILD_LDFLAGS -w ${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                flags=*)
                    GO_BUILD_LDFLAGS="$GO_BUILD_LDFLAGS -w "${OPTARG#*=}
                    ;;
                source)
                    GO_SOURCE_DIR="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                source=*)
                    GO_SOURCE_DIR=${OPTARG#*=}
                    ;;
                prefix)
                    DOCKER_IMAGE_PREFIX="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                prefix=*)
                    DOCKER_IMAGE_PREFIX=${OPTARG#*=}
                    ;;
                tag)
                    DOCKER_IMAGE_TAG="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                tag=*)
                    DOCKER_IMAGE_TAG=${OPTARG#*=}
                    ;;
                glide)
                    GLIDE_FILE="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                glide=*)
                    GLIDE_FILE=${OPTARG#*=}
                    ;;
                debug)
                    DEBUG=1
                    ;;
                cgo)
                    export CGO_ENABLED=1
                    ;;
                static)
                    GO_BUILD_LDFLAGS="-linkmode external -extldflags -static $GO_BUILD_LDFLAGS"
                    ;;
                race)
                    GO_BUILD_FLASG="-race $GO_BUILD_FLASG"
                    ;;
                *)
                    if [ "$OPTERR" = 1 ] && [ "${OPTSPEC:0:1}" != ":" ]; then
                        log_msg "error" "Unknown option --$OPTARG"
                    fi
                    ;;
            esac
            ;;
        *)
            echo "Go builder"
            exit 255
            ;;
  esac
done

shift $((OPTIND-1))

if [ "$DEBUG" = 1 ]; then
    set -x
fi

# install ssh private keys
for FILE_KEY in ~/.ssh/id_rsa
do
    if [ -f $FILE_KEY ]; then
        chmod 0600 $FILE_KEY
        echo "    IdentityFile $FILE_KEY" >> /etc/ssh/ssh_config
    fi
done

# install .netrc
if [ -s ".netrc" ] ; then
    cp .netrc ~/
    chmod 600 ~/.netrc
fi

if [ -s "./mirrors.yaml" ] && [ -n "$GLIDE_HOME" ]; then
  log_msg "debug" "Copy mirrors.yaml to $GLIDE_HOME"
  cp ./mirrors.yaml $GLIDE_HOME/
fi

if [ -n "$DOCKER_IMAGE_PREFIX" ]; then
    DOCKER_IMAGE_PREFIX=$DOCKER_IMAGE_PREFIX"/"
fi

# release main package
cd $GO_SOURCE_DIR

MAIN_PACKAGE_GO_IMPORT=`go list -e -f '{{.ImportComment}}' 2>/dev/null || true`
if [ "$MAIN_PACKAGE_GO_IMPORT" = "" ]; then
  MAIN_PACKAGE_GO_IMPORT=`go list -e -f '{{.Name}}' 2>/dev/null || true`
fi

# move source code to $GOPATH
GO_SOURCE_TARGET=${GO_SOURCE_PATH}${MAIN_PACKAGE_GO_IMPORT}
rm -rf $GO_SOURCE_TARGET
mkdir -p `dirname $GO_SOURCE_TARGET`
ln -sf $GO_SOURCE_DIR $GO_SOURCE_TARGET

do_go_get $MAIN_PACKAGE_GO_IMPORT "$GO_SOURCE_PATH"

set +e
do_release $MAIN_PACKAGE_GO_IMPORT "$GO_SOURCE_PATH"
RETURN_CODE=$?
set -e

if [ $RETURN_CODE -ne 0 ]; then
  exit $RETURN_CODE
fi

# release sub packages
cd $GO_SOURCE_TARGET

for GO_PACKAGE_PATH in `go list -e -f '{{.Dir}}' ./... 2>/dev/null | grep -v '^'$GO_SOURCE_DIR'$' | grep -v '^'$(pwd)"/vendor" || true`
do
  GO_PACKAGE=$MAIN_PACKAGE_GO_IMPORT${GO_PACKAGE_PATH##*$GO_SOURCE_TARGET}
  DOCKER_IMAGE_NAME=${DOCKER_IMAGE_PREFIX}${GO_PACKAGE##*/}

  set +e
  do_release $GO_PACKAGE "$GO_SOURCE_PATH" $DOCKER_IMAGE_NAME $DOCKER_IMAGE_TAG
  RETURN_CODE=$?
  set -e

  if [ $RETURN_CODE -ne 0 ]; then
    exit $RETURN_CODE
  fi
done