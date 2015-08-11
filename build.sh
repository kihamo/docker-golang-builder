#!/bin/bash

# set -x

echo "Start builder"

PACKAGE_COMPRESS=1
#PACKAGE_RACE=1
PACKAGE_GO_IMPORT=`go list -e -f '{{.ImportComment}}' 2>/dev/null || true`
MAIN_PACKAGE_PATH=$GOPATH"/src/"$PACKAGE_GO_IMPORT
BUILD_FLAGS=""
DOCKER_IMAGE_PREFIX=$1
DOCKER_IMAGE_VERSION=$2

if [ -n "DOCKER_IMAGE_PREFIX" ]; then
    DOCKER_IMAGE_PREFIX=$DOCKER_IMAGE_PREFIX"/"
fi

if [ -z "DOCKER_IMAGE_VERSION" ]; then
    DOCKER_IMAGE_VERSION="latest"
fi

#if [ $PACKAGE_RACE -eq 1 ]; then
#    BUILD_FLAGS=$BUILD_FLAGS" -race"
#fi

# For scratch sub containers
export GOOS=linux
export CGO_ENABLED=0

# cd $(go env GOROOT)/src && ./make.bash --no-clean && cd -

mkdir -p `dirname $MAIN_PACKAGE_PATH`
ln -sf /src $MAIN_PACKAGE_PATH

if [ -e "$MAIN_PACKAGE_PATH/Godeps/_workspace" ]; then
    GOPATH=$MAIN_PACKAGE_PATH/Godeps/_workspace:$GOPATH
else
    go get -t -d -v ./...
fi

for PACKAGE in $(go list -e -f '{{.ImportComment}}' ./... 2>/dev/null || true)
do
    echo "Build package $PACKAGE"

    PACKAGE_NAME=${PACKAGE##*/}

    cd $GOPATH"/src/"$PACKAGE
    go clean

    if [ -e "./Makefile" ]; then
        make build-pre
        make build
    fi

    if [ ! -e "./Makefile" ] || [ $? -ne 0 ]; then
        go build -v -a -tags netgo -installsuffix netgo -ldflags '-w' $BUILD_FLAGS .
    fi

    if [ $? -eq 0 ]; then
        if [ $PACKAGE_COMPRESS -eq 1 ]; then
          goupx $PACKAGE_NAME
        fi

        if [ -e "./Makefile" ]; then
            make build-post
        fi

        echo "Build package $PACKAGE SUCCESS"

        if [ -e "/var/run/docker.sock" ] && [ -e "./Dockerfile" ]; then
          DOCKER_IMAGE_NAME=${DOCKER_IMAGE_PREFIX}${PACKAGE_NAME}

          docker build -t ${DOCKER_IMAGE_NAME}":"${DOCKER_IMAGE_VERSION} ./

          if [ $DOCKER_IMAGE_VERSION -ne "latest" ]; then
            docker tag -f ${DOCKER_IMAGE_NAME}":"${DOCKER_IMAGE_VERSION} ${DOCKER_IMAGE_NAME}":latest"
          fi
        fi
    else
        echo "Build package $PACKAGE FAILED"
    fi
done