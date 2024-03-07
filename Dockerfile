# syntax=docker/dockerfile:1.7
# renovate: datasource=github-releases depName=redis/redis
ARG BUILD_VERSION=7.0.4

FROM docker.io/bitnami/minideb:bullseye as stage-0

COPY prebuildfs /
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN install_packages acl ca-certificates curl gzip libbz2-1.0 libc6-dev libssl-dev make tar procps zlib1g bzip2 build-essential g++ pkg-config libssh2-1-dev libldap2-dev
RUN mkdir -p /opt/src/redis /opt/bitnami/redis/etc /opt/bitnami/redis/licenses

COPY --link --from=ghcr.io/bitcompat/gosu:1.14.0-bullseye-r1 /opt/bitnami/ /opt/bitnami/
COPY --link --from=ghcr.io/bitcompat/wait-for-port:1.0.3-bullseye-r1 /opt/bitnami/ /opt/bitnami/

ARG BUILD_VERSION
ARG REDIS_DOWNLOAD_URL=http://download.redis.io/releases/redis-${BUILD_VERSION}.tar.gz
ARG REDIS_BASEDIR=/opt/bitnami/redis

ADD --link $REDIS_DOWNLOAD_URL /opt/src/redis.tar.gz
ADD --link https://raw.githubusercontent.com/redis/redis-hashes/master/README /opt/src/README.md

WORKDIR /opt/src
RUN <<EOT /bin/bash
    set -eux
	cat README.md | grep -F ${BUILD_VERSION} | grep sha256 | awk '{print \$4,"redis.tar.gz"}' | sha256sum -c -
	tar -xzf redis.tar.gz -C /opt/src/redis --strip-components=1

# disable Redis protected mode [1] as it is unnecessary in context of Docker
# (ports are not automatically exposed when running inside Docker, but rather explicitly by specifying -p / -P)
# [1]: https://github.com/redis/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
	grep -E '^ *createBoolConfig[(]"protected-mode",.*, *1 *,.*[)],\$' /opt/src/redis/src/config.c
	sed -ri 's!^( *createBoolConfig[(]"protected-mode",.*, *)1( *,.*[)],)\$!\10\2!' /opt/src/redis/src/config.c
	grep -E '^ *createBoolConfig[(]"protected-mode",.*, *0 *,.*[)],\$' /opt/src/redis/src/config.c

# for future reference, we modify this directly in the source instead of just supplying a default configuration flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
# see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
# (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)

# https://github.com/jemalloc/jemalloc/issues/467 -- we need to patch the "./configure" for the bundled jemalloc to match how Debian compiles, for compatibility
# (also, we do cross-builds, so we need to embed the appropriate "--build=xxx" values to that "./configure" invocation)
	gnuArch="\$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
	extraJemallocConfigureFlags="--build=\$gnuArch"
# https://salsa.debian.org/debian/jemalloc/-/blob/c0a88c37a551be7d12e4863435365c9a6a51525f/debian/rules#L8-23
	dpkgArch="\$(dpkg --print-architecture)"
	case "\${dpkgArch##*-}" in
		amd64 | i386 | x32) extraJemallocConfigureFlags="\$extraJemallocConfigureFlags --with-lg-page=12" ;;
		*) extraJemallocConfigureFlags="\$extraJemallocConfigureFlags --with-lg-page=16" ;;
	esac
	extraJemallocConfigureFlags="\$extraJemallocConfigureFlags --with-lg-hugepage=21"
	grep -F 'cd jemalloc && ./configure ' /opt/src/redis/deps/Makefile
	sed -ri 's!cd jemalloc && ./configure !&'"\$extraJemallocConfigureFlags"' !' /opt/src/redis/deps/Makefile
	grep -F "cd jemalloc && ./configure \$extraJemallocConfigureFlags " /opt/src/redis/deps/Makefile

	export BUILD_TLS=yes
	make -C /opt/src/redis -j "\$(nproc)" all PREFIX=${REDIS_BASEDIR}
	make -C /opt/src/redis install PREFIX=${REDIS_BASEDIR}

	cp -f /opt/src/redis/redis.conf /opt/bitnami/redis/etc/redis-default.conf
	cp -f /opt/src/redis/COPYING /opt/bitnami/redis/licenses/redis-${BUILD_VERSION}.txt
	rm -r /opt/src/redis

    PATH=${REDIS_BASEDIR}/bin:\$PATH
	redis-cli --version
	redis-server --version
EOT

COPY --link rootfs /
RUN <<EOT bash
    set -ex
    chmod g+rwX /opt/bitnami

    rm -rf \
      /opt/bitnami/common/share \
      /opt/bitnami/common/lib/*.{a,la}

    strip --strip-all ${REDIS_BASEDIR}/bin/* || true
    strip --strip-all /opt/bitnami/common/bin/* || true
EOT

FROM docker.io/bitnami/minideb:bullseye AS stage-1

ARG BUILD_VERSION
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
LABEL org.opencontainers.image.ref.name="${SERVER_VERSION}-debian-11-r0" \
      org.opencontainers.image.version="${SERVER_VERSION}"

COPY --from=stage-0 /opt/bitnami /opt/bitnami
RUN <<EOT /bin/bash
    set -e
    install_packages acl ca-certificates procps zlib1g tzdata libssh2-1 libldap-2.4-2 curl libgnutls30 libtirpc3
    ln -s /opt/bitnami/scripts/redis/entrypoint.sh /entrypoint.sh
    ln -s /opt/bitnami/scripts/redis/run.sh /run.sh
    /opt/bitnami/scripts/redis/postunpack.sh
EOT

ENV HOME="/" \
    OS_ARCH="$TARGETPLATFORM" \
    OS_FLAVOUR="debian-11" \
    OS_NAME="linux" \
    APP_VERSION="${BUILD_VERSION}" \
    BITNAMI_APP_NAME="redis" \
    PATH="/opt/bitnami/common/bin:/opt/bitnami/redis/bin:$PATH"

EXPOSE 6379
USER 1001
ENTRYPOINT [ "/opt/bitnami/scripts/redis/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/redis/run.sh" ]
