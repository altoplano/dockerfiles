#!/bin/bash
UPSTREAMS=${1:-""}
WEBSOCKET_BACKENDS=${WEBSOCKET_BACKENDS:-""}

show_usage() {
    echo "Usage: $0 [upstreams]
    The following environment variables are available
    for customization of the backend:

    WEBSOCKET_BACKENDS: space separated list of Websocket backends to upgrade
    "
}

if [ -z "$UPSTREAMS" ]; then
    show_usage
    exit 1
fi

echo "configuring proxy"

CONF="
user  nginx;
worker_processes  1;
daemon off;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

"

if [ ! -z "$WEBSOCKET_BACKENDS" ]; then
    CONF="$CONF
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
}
"
fi

CONF="$CONF
    upstream up {
"
for UP in $UPSTREAMS; do
    echo "adding upstream: $UP"
    CONF="$CONF
        server $UP;
"
done
    CONF="$CONF
    }

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] \"\$request\" '
                      '\$status \$body_bytes_sent \"\$http_referer\" '
                      '\"\$http_user_agent\" \"\$http_x_forwarded_for\"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

"

CONF="$CONF
    server {
        listen 80;
        location / {
            proxy_pass http://up;
            proxy_connect_timeout       600;
            proxy_send_timeout          600;
            proxy_read_timeout          600;
            send_timeout                600;
        }
"
for WS in $WEBSOCKET_BACKENDS; do
    echo "adding websocket backend: $WS"
    CONF="$CONF
    location $WS {
        proxy_pass http://up;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
    }
"
done

CONF="$CONF
    }
}
"

echo "$CONF" > /etc/nginx/nginx.conf

echo "proxy running"
exec nginx -c /etc/nginx/nginx.conf
