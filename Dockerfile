FROM golang:1.4
MAINTAINER Kihamo <dev@kihamo.ru>

RUN apt-get update && \
    apt-get install --no-install-recommends -y docker upx-ucl zip && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    apt-get purge -y

RUN curl -sSL -O https://get.docker.com/builds/Linux/x86_64/docker-1.7.0 && \
    chmod +x docker-1.7.0 && \
    mv docker-1.7.0 /usr/local/bin/docker

RUN go get -t -v github.com/pwaller/goupx

VOLUME /src
WORKDIR /src

COPY build.sh /build.sh

ENTRYPOINT ["/build.sh"]