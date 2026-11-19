FROM alpine:3.24
RUN apk add --no-cache bash coreutils findutils grep sed gawk curl jq docker-cli util-linux-misc tzdata
COPY scan.sh entrypoint.sh /app/
RUN chmod 755 /app/*.sh
ENTRYPOINT ["/app/entrypoint.sh"]
