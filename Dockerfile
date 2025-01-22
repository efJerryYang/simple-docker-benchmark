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
    iperf3 \
    dos2unix

WORKDIR /benchmark

COPY scripts/benchmark.sh /benchmark/
COPY scripts/entrypoint.sh /benchmark/

RUN dos2unix /benchmark/benchmark.sh /benchmark/entrypoint.sh && \
    chmod +x /benchmark/*.sh
ENTRYPOINT ["/benchmark/entrypoint.sh"]
