FROM alpine:3.20

RUN apk add --no-cache \
    docker-cli \
    docker-cli-compose \
    python3 \
    curl

WORKDIR /workspace

COPY docker/finalizer/finalizer.sh /usr/local/bin/finalizer.sh


CMD ["/usr/local/bin/finalizer.sh"]
