FROM alpine:latest

RUN apk add --no-cache \
    bash \
    coreutils \
    curl \
    procps \
    gzip \
    iputils \
    parallel \
    bc \
    bind-tools \
    jq \
    iperf3

WORKDIR /benchmark

COPY scripts/benchmark.sh /benchmark/
COPY scripts/entrypoint.sh /benchmark/

RUN chmod +x /benchmark/*.sh

ENTRYPOINT ["/benchmark/entrypoint.sh"]
