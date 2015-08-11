#!/bin/sh

set -e
#if [ -n "$BASH" ]; then
#  set -o pipefaili
#fi

DEBUG=0

GO_SOURCE_DIR="/src"
GO_PACKAGE_COMPRESS=0
GO_BUILD_FLAGS=""

DOCKER_IMAGE_PREFIX=""
DOCKER_IMAGE_TAG="latest"

# colors
CL_RESET="\033[0m"
CL_RED="\033[31m"
CL_GREEN="\033[32m"
CL_BLUE="\033[34m"

# Update packages
# $1 - main package
do_go_get() {
  mkdir -p `dirname $GOPATH"/src/"$1`
  ln -sf $GO_SOURCE_DIR $GOPATH"/src/"$1

  if [ -e "$1/Godeps/_workspace" ]; then
    GOPATH=$1/Godeps/_workspace:$GOPATH
  else
    go get -t -d -v ./...
  fi
}

# Build binary
# $1 - package name
# $2 - build flags
# $3 - compress binary
do_go_build() {
  export GOOS=linux
  export CGO_ENABLED=0

  echo ${CL_BLUE}"Build Go package $1"${CL_RESET}

  cd $GOPATH"/src/"$1
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
    echo ${CL_BLUE}"Build Docker image $1"${CL_RESET}

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
    echo "\n  ${CL_RED}Error:${CL_RESET} ${CL_BLUE}$1${CL_RESET}" >&2
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

  do_go_build "$GO_PACKAGE_PATH" "$GO_BUILD_FLAGS" $GO_PACKAGE_COMPRESS
  do_docker_build $DOCKER_IMAGE_NAME $DOCKER_IMAGE_TAG
done