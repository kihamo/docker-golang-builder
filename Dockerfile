FROM golang:1.5
MAINTAINER Kihamo <dev@kihamo.ru>

RUN apt-get update && \
    apt-get install --no-install-recommends -y upx-ucl zip && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    apt-get purge -y

RUN curl -sSL -O https://get.docker.com/builds/Linux/x86_64/docker-1.9.1 && \
    chmod +x docker-1.9.1 && \
    mv docker-1.9.1 /usr/local/bin/docker

VOLUME /src
WORKDIR /src

COPY build.sh /build.sh

ENTRYPOINT ["/build.sh"]
