FROM alpine:3.23 AS build

RUN apk add --no-cache crystal shards openssl-dev gc-static zlib-static openssl-libs-static pcre2-static upx

WORKDIR /build

COPY shard.yml shard.lock ./
RUN shards install --production

COPY . .
RUN crystal build src/mailcatcher.cr --release --static --no-debug --link-flags="-s" -o mailcatcher && \
    upx --best --lzma mailcatcher

FROM scratch
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /build/mailcatcher /mailcatcher

ENTRYPOINT ["/mailcatcher", "--foreground", "--ip", "::"]
EXPOSE 1080 1025
CMD ["--no-quit"]
