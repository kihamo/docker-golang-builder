#!/bin/sh

set -e
#if [ -n "$BASH" ]; then
#  set -o pipefaili
#fi

export GOOS=linux
export CGO_ENABLED=0

DEBUG=0
DEPS_LOADED=0

GO_SOURCE_DIR="/src"
GO_VENDOR_DIR=$GO_SOURCE_DIR"/vendor"
GO_PATH=$GOPATH

GO_PACKAGE_COMPRESS=0
GO_BUILD_STATIC=0
GO_BUILD_FLAGS=""

GLIDE_YAML="glide.yaml"

DOCKER_IMAGE_PREFIX=""
DOCKER_IMAGE_TAG="latest"

# colors
CL_RESET="\033[0m"
CL_RED="\033[31m"
CL_GREEN="\033[32m"
CL_YELLOW="\033[33m"

# Update packages
# $1 [string] main package import path
do_go_get() {
  if [ $DEPS_LOADED -eq 1 ]; then
    log_msg "debug" "Dependencies already loaded."
    return
  fi

  PACKAGE_DIR=$GO_PATH"/src/"$1

  if [ -e "$PACKAGE_DIR/$GLIDE_YAML" ]; then
      log_msg "debug" "Find Glide in $1"

      export GO15VENDOREXPERIMENT=1

      if [ $DEBUG -eq 0 ]; then
        glide -y $GLIDE_YAML install
      else
        glide -y $GLIDE_YAML --debug install
      fi
  elif [ -e "$PACKAGE_DIR/Godeps/_workspace" ]; then
    log_msg "debug" "Find Godep in $1"

    if [ `find $PACKAGE_DIR/Godeps/_workspace/src -mindepth 1 -type d | wc -l` -eq 0 ]; then
      if [ $DEBUG -eq 0 ]; then
        godep restore
      else
        godep restore -v
      fi

    else
      export GOPATH=$PACKAGE_DIR/Godeps/_workspace:$GOPATH
      export PATH=$PACKAGE_DIR/Godeps/_workspace/bin:$PATH
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
}

# Build binary
# $1 [string]  package name
# $2 [string]  build flags
# $3 [boolean] compress binary
do_go_build() {
  log_msg "info" "Build Go package $1"

  cd $GO_PATH"/src/"$1

  if [ `go list -e -f '{{.Name}}' 2>/dev/null || true` != "main" ]; then
    log_msg "warn" "Ignore build package $1. Not found main package"
    return 2
  fi

  go clean

  if [ -e "./Makefile" ]; then
    set +e
    make build-pre
    make build
    set -e
  fi

  if [ ! -e "./Makefile" ] || [ $? -ne 0 ]; then
    LDFLAGS="-s"

    if [ -n "$2" ]; then
      LDFLAGS="$LDFLAGS -w $2"
    fi

    if [ $GO_BUILD_STATIC -eq 1 ]; then
      LDFLAGS="-linkmode external -extldflags -static $LDFLAGS"
    fi

    if [ $DEBUG -eq 0 ]; then
      go build -a -tags netgo -installsuffix netgo -ldflags "$LDFLAGS" .
    else
      go build -v -a -tags netgo -installsuffix netgo -ldflags "$LDFLAGS" .
    fi
  fi

  if [ $? -eq 0 ]; then
    if [ $3 -eq 1 ]; then
      goupx --strip-binary ${1##*/}
    fi

    if [ -e "./Makefile" ]; then
      set +e
      make build-post
      set -e
    fi

    log_msg "info" "Build Go package $1 SUCCESS"
  else
    log_msg "fatal" "Build package $1 FAILED"
    return 1
  fi

  return 0
}

# Build docker image
# $1 [string] image name
# $2 [string] image version
do_docker_build() {
  if [ -e "/var/run/docker.sock" ] && [ -e "./Dockerfile" ]; then
    log_msg "info" "Build Docker image $1"

    docker build -t $1":"$2 ./

    if [ "$2" != "latest" ]; then
      docker tag -f $1":"$2 $1":latest"
    fi

    log_msg "info" "Build Docker image $1 SUCCESS"
  fi

  return 0
}

# Release package
# $1 [string] package import path
do_release() {
  do_go_get $1

  set +e
  do_go_build "$1" "$GO_BUILD_FLAGS" $GO_PACKAGE_COMPRESS
  RESULT=$?
  set -e

  if [ $RESULT -eq 0 ]; then
    GO_PACKAGE_NAME=${1##*/}
    DOCKER_IMAGE_NAME=${DOCKER_IMAGE_PREFIX}${GO_PACKAGE_NAME}

    do_docker_build $DOCKER_IMAGE_NAME $DOCKER_IMAGE_TAG
  fi
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
         exit 255
         ;;
      "fatal")
         shift
         echo "${CL_RED}[FATAL]${CL_RESET} $@" >&2
         echo "$USAGE"
         exit 255
         ;;
      "error")
         shift
         echo "${CL_RED}[ERROR]${CL_RESET} $@" >&2
         echo "$USAGE"
         exit 255
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
                    GO_BUILD_FLAGS="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                flags=*)
                    GO_BUILD_FLAGS=${OPTARG#*=}
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
                    GLIDE_YAML="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                glide=*)
                    GLIDE_YAML=${OPTARG#*=}
                    ;;
                debug)
                    DEBUG=1
                    ;;
                cgo)
                    export CGO_ENABLED=1
                    ;;
                static)
                    export GO_BUILD_STATIC=1
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
        echo "    IdentityFile $FILE_KEY" >> /etc/ssh/ssh_config
    fi
done

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
rm -rf $GO_PATH"/src/"$MAIN_PACKAGE_GO_IMPORT
mkdir -p `dirname $GO_PATH"/src/"$MAIN_PACKAGE_GO_IMPORT`
ln -sf $GO_SOURCE_DIR $GO_PATH"/src/"$MAIN_PACKAGE_GO_IMPORT

do_release $MAIN_PACKAGE_GO_IMPORT

# release sub packages
cd $GO_SOURCE_DIR

for GO_PACKAGE_PATH in `go list -e -f '{{.Dir}}' ./... 2>/dev/null | grep -v '^'$GO_SOURCE_DIR'$' | grep -v '^'$GO_VENDOR_DIR || true`
do
  cd $GO_PACKAGE_PATH
  if [ `go list -e -f '{{.Name}}' 2>/dev/null || true` != "main" ]; then
    continue
  fi
  cd -

  do_release "$MAIN_PACKAGE_GO_IMPORT${GO_PACKAGE_PATH##*$GO_SOURCE_DIR}"
done