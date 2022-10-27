FROM mtr.devops.telekom.de/tardis-common/kong:2.8.1-alpine

USER root

RUN set -ex && apk add --no-cache curl gcc libc-dev

ADD / /tmp/kong

WORKDIR /tmp/kong

#RUN cd kong-plugin-jwt-keycloak && luarocks make
#RUN cd eni-zipkin && luarocks make
#RUN cd kong-plugin-eni-prometheus && luarocks make
RUN ls
RUN cd kong/plugins/eni-zipkin && luarocks make

USER kong

RUN mkdir -p /usr/local/kong/plugins

RUN git config --global url.https://github.com/.insteadOf git://github.com

WORKDIR /usr/local/kong/plugins

# If you want to download and add a plugin
#RUN \
#    luarocks install --local kong-plugin-xyz && \
#    luarocks pack --local kong-plugin-xyz

RUN \
    luarocks install --local luaossl OPENSSL_DIR=/usr/local/kong CRYPTO_DIR=/usr/local/kong && \
    luarocks pack --local luaossl

RUN luarocks list
# If you just want to add a plugin from the source code comitted with this pipeline (/plugins dir)
RUN luarocks pack lua-cjson
#RUN luarocks pack kong-plugin-jwt-keycloak
RUN luarocks pack eni-zipkin
#RUN luarocks pack kong-plugin-eni-prometheus
RUN luarocks pack lua-resty-http
RUN luarocks pack lua-resty-counter

#RUN rm -rf /home/kong/.luarocks
