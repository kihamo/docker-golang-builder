FROM golang:1.6
MAINTAINER Kihamo <dev@kihamo.ru>

ENV GOBIN $GOPATH/bin

RUN apt-get update && \
    apt-get install --no-install-recommends -y upx-ucl zip && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    apt-get purge -y

# install Docker
RUN curl -sSL -O https://get.docker.com/builds/Linux/x86_64/docker-1.7.1 && \
    chmod +x docker-1.7.1 && \
    mv docker-1.7.1 /usr/local/bin/docker

# install Glide
RUN mkdir -p $GOPATH"/src/github.com/Masterminds/glide" && \
    cd $GOPATH"/src/github.com/Masterminds/glide" && \
    git clone https://github.com/Masterminds/glide.git . && \
    git checkout 0.10.2 && \
    export GO15VENDOREXPERIMENT=1 && \
    make clean && \
    make bootstrap && \
    make build && \
    mv glide $GOBIN/glide

# install Godep
RUN mkdir -p $GOPATH"/src/github.com/tools/godep" && \
    cd $GOPATH"/src/github.com/tools/godep" && \
    git clone https://github.com/tools/godep.git . && \
    git checkout v57 && \
    go install

# install goupx
RUN go get -t github.com/pwaller/goupx

VOLUME /src
WORKDIR /src

COPY build.sh /build.sh

ENTRYPOINT ["/build.sh"]
