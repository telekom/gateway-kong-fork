FROM mtr.devops.telekom.de/tardis-common/kong:2.8.1-alpine as builder

USER root

RUN set -ex && apk add --no-cache curl gcc libc-dev tree
RUN apk upgrade

ADD / /tmp/kong
WORKDIR /tmp/kong

RUN luarocks make

USER kong
