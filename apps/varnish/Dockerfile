FROM varnish:7.6-alpine

COPY default.vcl /etc/varnish/default.vcl

EXPOSE 80

CMD ["varnishd", "-F", "-f", "/etc/varnish/default.vcl", "-a", "http=:80,HTTP", "-p", "default_ttl=120"]
