FROM varnish:7.6-alpine

COPY default.vcl.template /etc/varnish/default.vcl.template
COPY --chmod=755 docker-entrypoint.sh /docker-entrypoint.sh

ENV BACKEND_HOST=api

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]

