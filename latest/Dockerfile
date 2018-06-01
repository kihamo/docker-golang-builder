FROM golang:1.9.4
MAINTAINER Kihamo <dev@kihamo.ru>

ENV GOBIN $GOPATH/bin

RUN apt-get update && \
    apt-get install --no-install-recommends -y upx-ucl zip && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    apt-get purge -y

# install Docker
RUN curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-18.03.1-ce.tgz && \
    tar --strip-components=1 -xvzf docker-18.03.1-ce.tgz -C /usr/local/bin

# Golang dep
RUN curl -fsSL https://github.com/golang/dep/releases/download/v0.4.1/dep-linux-amd64 -o ./dep && \
    chmod +x ./dep && \
    mv ./dep /usr/local/bin/

# install Glide
RUN mkdir -p $GOPATH"/src/github.com/Masterminds/glide" && \
    cd $GOPATH"/src/github.com/Masterminds/glide" && \
    git clone https://github.com/Masterminds/glide.git . && \
    git checkout v0.13.1 && \
    make build && \
    mv glide $GOBIN/glide

# install Godep
RUN mkdir -p $GOPATH"/src/github.com/tools/godep" && \
    cd $GOPATH"/src/github.com/tools/godep" && \
    git clone https://github.com/tools/godep.git . && \
    git checkout v80 && \
    go install

# install goupx
RUN go get -t github.com/pwaller/goupx

# ssh
RUN sed -i.bak /etc/ssh/ssh_config -e '/StrictHostKeyChecking/d' /etc/ssh/ssh_config && \
    echo "    StrictHostKeyChecking no" >> /etc/ssh/ssh_config

VOLUME /src
WORKDIR /src

COPY build.sh /usr/local/bin/go-build
RUN chmod +x /usr/local/bin/go-build

ENTRYPOINT ["go-build"]
