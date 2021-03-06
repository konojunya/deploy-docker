FROM node:8.4-alpine

RUN apk add --no-cache \
    git curl tar \
    openssh-client


######### golang
RUN apk add --no-cache \
    ca-certificates

# set up nsswitch.conf for Go's "netgo" implementation
# - https://github.com/golang/go/blob/go1.9.1/src/net/conf.go#L194-L275
# - docker run --rm debian:stretch grep '^hosts:' /etc/nsswitch.conf
RUN [ ! -e /etc/nsswitch.conf ] && echo 'hosts: files dns' > /etc/nsswitch.conf

ENV GOLANG_VERSION 1.11

RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
    bash \
    gcc \
    musl-dev \
    openssl \
    go \
    ; \
    export \
    # set GOROOT_BOOTSTRAP such that we can actually build Go
    GOROOT_BOOTSTRAP="$(go env GOROOT)" \
    # ... and set "cross-building" related vars to the installed system's values so that we create a build targeting the proper arch
    # (for example, if our build host is GOARCH=amd64, but our build env/image is GOARCH=386, our build needs GOARCH=386)
    GOOS="$(go env GOOS)" \
    GOARCH="$(go env GOARCH)" \
    GOHOSTOS="$(go env GOHOSTOS)" \
    GOHOSTARCH="$(go env GOHOSTARCH)" \
    ; \
    # also explicitly set GO386 and GOARM if appropriate
    # https://github.com/docker-library/golang/issues/184
    apkArch="$(apk --print-arch)"; \
    case "$apkArch" in \
    armhf) export GOARM='6' ;; \
    x86) export GO386='387' ;; \
    esac; \
    \
    wget -O go.tgz "https://golang.org/dl/go$GOLANG_VERSION.src.tar.gz"; \
    echo 'afc1e12f5fe49a471e3aae7d906c73e9d5b1fdd36d52d72652dde8f6250152fb *go.tgz' | sha256sum -c -; \
    tar -C /usr/local -xzf go.tgz; \
    rm go.tgz; \
    \
    cd /usr/local/go/src; \
    ./make.bash; \
    \
    rm -rf \
    # https://github.com/golang/go/blob/0b30cf534a03618162d3015c8705dd2231e34703/src/cmd/dist/buildtool.go#L121-L125
    /usr/local/go/pkg/bootstrap \
    # https://golang.org/cl/82095
    # https://github.com/golang/build/blob/e3fe1605c30f6a3fd136b561569933312ede8782/cmd/release/releaselet.go#L56
    /usr/local/go/pkg/obj \
    ; \
    apk del .build-deps; \
    \
    export PATH="/usr/local/go/bin:$PATH"; \
    go version

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"


######### golang end

RUN apk add --no-cache make py-pip bash jq ca-certificates
RUN pip install --no-cache-dir awscli awslogs

ENV DOCKER_CHANNEL stable
ENV DOCKER_VERSION 17.06.1-ce
# TODO ENV DOCKER_SHA256
# https://github.com/docker/docker-ce/blob/5b073ee2cf564edee5adca05eee574142f7627bb/components/packaging/static/hash_files !!
# (no SHA file artifacts on download.docker.com yet as of 2017-06-07 though)

RUN set -ex; \
    # why we use "curl" instead of "wget":
    # + wget -O docker.tgz https://download.docker.com/linux/static/stable/x86_64/docker-17.03.1-ce.tgz
    # Connecting to download.docker.com (54.230.87.253:443)
    # wget: error getting response: Connection reset by peer
    apk add --no-cache --virtual .fetch-deps \
    curl \
    tar \
    ; \
    \
    # this "case" statement is generated via "update.sh"
    apkArch="$(apk --print-arch)"; \
    case "$apkArch" in \
    x86_64) dockerArch='x86_64' ;; \
    s390x) dockerArch='s390x' ;; \
    *) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;;\
    esac; \
    \
    if ! curl -fL -o docker.tgz "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/${dockerArch}/docker-${DOCKER_VERSION}.tgz"; then \
    echo >&2 "error: failed to download 'docker-${DOCKER_VERSION}' from '${DOCKER_CHANNEL}' for '${dockerArch}'"; \
    exit 1; \
    fi; \
    \
    tar --extract \
    --file docker.tgz \
    --strip-components 1 \
    --directory /usr/local/bin/ \
    ; \
    rm docker.tgz; \
    \
    apk del .fetch-deps; \
    \
    dockerd -v; \
    docker -v

# Download and install the cloud sdk
RUN apk add --update openssl
RUN wget https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz --no-check-certificate \
    && tar zxvf google-cloud-sdk.tar.gz \
    && rm google-cloud-sdk.tar.gz \
    && ls -l \
    && ./google-cloud-sdk/install.sh --usage-reporting=true --path-update=true

# Add gcloud to the path
ENV PATH /google-cloud-sdk/bin:$PATH

# Configure gcloud for your project
RUN yes | gcloud components update
RUN yes | gcloud components update preview

# heroku cli install
RUN npm install -g heroku-cli

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh"]
