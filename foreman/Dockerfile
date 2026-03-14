ARG FOREMAN_IMAGE=quay.io/foreman/foreman:3.18
FROM ${FOREMAN_IMAGE}

USER root

COPY entrypoint.sh /usr/local/bin/foreman-app-entrypoint.sh
RUN chmod 0755 /usr/local/bin/foreman-app-entrypoint.sh && \
    mkdir -p /etc/foreman /etc/foreman/plugins /var/lib/foreman /var/log/foreman /var/run/foreman

ENTRYPOINT ["/usr/local/bin/foreman-app-entrypoint.sh"]
