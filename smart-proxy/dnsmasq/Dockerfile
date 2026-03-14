FROM alpine:3.20

RUN apk add --no-cache bash dnsmasq

COPY dnsmasq/entrypoint.sh /entrypoint.sh
COPY dnsmasq.managed.conf /templates/managed.conf
COPY dnsmasq.external.conf /templates/external.conf
RUN chmod 0755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
