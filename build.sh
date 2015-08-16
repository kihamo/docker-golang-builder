#!/bin/sh

set -e
#if [ -n "$BASH" ]; then
#  set -o pipefaili
#fi

DEBUG=0

GO_SOURCE_DIR="/src"
GO_PACKAGE_COMPRESS=0
GO_BUILD_FLAGS=""
GO_PATH=$GOPATH

DOCKER_IMAGE_PREFIX=""
DOCKER_IMAGE_TAG="latest"

# colors
CL_RESET="\033[0m"
CL_RED="\033[31m"
CL_GREEN="\033[32m"
CL_YELLOW="\033[33m"

# Update packages
# $1 - main package
do_go_get() {
  PACKAGE_DIR=$GO_PATH"/src/"$1

  mkdir -p `dirname $GO_PATH"/src/"$1`
  ln -sf $GO_SOURCE_DIR $GO_PATH"/src/"$1

  if [ -e "$GO_SOURCE_DIR/Godeps/_workspace" ]; then
    if [ `find $GO_SOURCE_DIR/Godeps/_workspace/src -mindepth 1 -type d | wc -l` -eq 0 ]; then
      go get -t -v github.com/tools/godep

      if [ $DEBUG -eq 0 ]; then
        godep restore -v
      else
        godep restore
      fi
    else
      export GOPATH=$GO_SOURCE_DIR/Godeps/_workspace:$GOPATH
      export PATH=$GO_SOURCE_DIR/Godeps/_workspace/bin:$PATH
    fi
  else
    if [ $DEBUG -eq 0 ]; then
      go get -t -d -v ./...
    else
      go get -t -d ./...
    fi
  fi
}

# Build binary
# $1 - package name
# $2 - build flags
# $3 - compress binary
do_go_build() {
  export GOOS=linux
  export CGO_ENABLED=0

  echo ${CL_YELLOW}"Build Go package $1"${CL_RESET}

  cd $GO_PATH"/src/"$1

  PACKAGE_NAME=`go list -e -f '{{.Name}}' 2>/dev/null || true`
  if [ "$PACKAGE_NAME" != "main" ]; then
    echo ${CL_YELLOW}"Ignore build package $1. Not found main package"${CL_RESET}
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
    go build -v -a -tags netgo -installsuffix netgo -ldflags "-w $2" .
  fi

  if [ $? -eq 0 ]; then
    if [ $3 -eq 1 ]; then
      goupx ${1##*/}
    fi

    if [ -e "./Makefile" ]; then
      set +e
      make build-post
      set -e
    fi

    echo ${CL_GREEN}"Build Go package $1 SUCCESS"${CL_RESET}
  else
    print_error "Build package $1 FAILED"
    return 1
  fi

  return 0
}

# Build docker image
# $1 - image name
# $2 - image version
do_docker_build() {
  if [ -e "/var/run/docker.sock" ] && [ -e "./Dockerfile" ]; then
    echo ${CL_YELLOW}"Build Docker image $1"${CL_RESET}

    docker build -t $1":"$2 ./

    if [ "$2" != "latest" ]; then
      docker tag -f $1":"$2 $1":latest"
    fi

    echo ${CL_GREEN}"Build Docker image $1 SUCCESS"${CL_RESET}
  fi

  return 0
}

# Print critical error and exit
# $1 - is the error message
print_error() {
    echo "\n  ${CL_RED}Error:${CL_RESET} ${CL_YELLOW}$1${CL_RESET}" >&2
    echo "$USAGE"
    exit 255
}

OPTSPEC=":-:"
while getopts "$OPTSPEC" OPT; do
  case $OPT in
        -)
            case "$OPTARG" in
                compress)
                    GO_PACKAGE_COMPRESS=1
                    go get -t -v github.com/pwaller/goupx
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
                debug)
                    DEBUG=1
                    ;;
                *)
                    if [ "$OPTERR" = 1 ] && [ "${OPTSPEC:0:1}" != ":" ]; then
                        print_error "Unknown option --$OPTARG"
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

if [ -n "$DOCKER_IMAGE_PREFIX" ]; then
    DOCKER_IMAGE_PREFIX=$DOCKER_IMAGE_PREFIX"/"
fi

cd $GO_SOURCE_DIR
PACKAGE_GO_IMPORT=`go list -e -f '{{.ImportComment}}' 2>/dev/null || true`
do_go_get $PACKAGE_GO_IMPORT

for GO_PACKAGE_PATH in `go list -e -f '{{.ImportComment}}' ./... 2>/dev/null || true`
do
  GO_PACKAGE_NAME=${GO_PACKAGE_PATH##*/}
  DOCKER_IMAGE_NAME=${DOCKER_IMAGE_PREFIX}${GO_PACKAGE_NAME}

  set +e
  do_go_build "$GO_PACKAGE_PATH" "$GO_BUILD_FLAGS" $GO_PACKAGE_COMPRESS
  RESULT=$?
  set -e

  if [ $RESULT -eq 0 ]; then
    do_docker_build $DOCKER_IMAGE_NAME $DOCKER_IMAGE_TAG
  fi
done
