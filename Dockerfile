ARG osdistro=ubuntu
ARG oscodename=focal

FROM $osdistro:$oscodename
LABEL maintainer="Walter Doekes <wjdoekes+sedutil@osso.nl>"

ARG DEBIAN_FRONTEND=noninteractive

# ubuntu, ubu, focal, sedutil, 1.15.1, '', 0osso1
ARG osdistro
ARG osdistshort
ARG oscodename
ARG upname
ARG upversion
ARG debepoch=
ARG debversion

ARG upsrc_md5=610301fca946d515251c30a4e26bd6a0

# Copy debian dir, check version
RUN mkdir -p /build/debian
COPY ./changelog /build/debian/changelog
RUN . /etc/os-release && fullversion="${upversion}-${debversion}+${osdistshort}${VERSION_ID}" && \
    expected="${upname} (${debepoch}${fullversion}) ${oscodename}; urgency=medium" && \
    head -n1 /build/debian/changelog && \
    if test "$(head -n1 /build/debian/changelog)" != "${expected}"; \
    then echo "${expected}  <-- mismatch" >&2; false; fi

# This time no "keeping the build small". We only use this container for
# building/testing and not for running, so we can keep files like apt
# cache.
RUN echo 'APT::Install-Recommends "0";' >/etc/apt/apt.conf.d/01norecommends
RUN apt-get update -q
RUN apt-get install -y apt-utils
RUN apt-get dist-upgrade -y
RUN apt-get install -y \
    bzip2 ca-certificates curl git \
    build-essential dh-autoreconf devscripts dpkg-dev equivs quilt

# Set up upstream source, move debian dir and jump into dir.
#
# Trick to allow caching of SOURCE*.tar.gz files. Download them
# once using the curl command below into .cache/* if you want. The COPY
# is made conditional by the "[2]" "wildcard". (We need one existing
# file (README.rst) so the COPY doesn't fail.)
COPY ./README.rst .cache/${upname}_${upversion}.orig.tar.g[z] /build/
RUN if ! test -s /build/${upname}_${upversion}.orig.tar.gz; then \
    url="https://codeload.github.com/Drive-Trust-Alliance/sedutil/tar.gz/${upversion}" && \
    echo "Fetching: ${url}" >&2 && \
    curl --fail "${url}" >/build/${upname}_${upversion}.orig.tar.gz; fi
RUN test $(md5sum /build/${upname}_${upversion}.orig.tar.gz | awk '{print $1}') = ${upsrc_md5}
RUN cd /build && tar zxf "${upname}_${upversion}.orig.tar.gz" && \
    mv debian "${upname}-${upversion}/"
WORKDIR "/build/${upname}-${upversion}"

# Apt-get prerequisites according to control file.
COPY ./control debian/control
RUN mk-build-deps --install --remove --tool "apt-get -y" debian/control

# Set up build env
RUN printf "%s\n" \
    QUILT_PATCHES=debian/patches \
    QUILT_NO_DIFF_INDEX=1 \
    QUILT_NO_DIFF_TIMESTAMPS=1 \
    'QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"' \
    'QUILT_DIFF_OPTS="--show-c-function"' \
    >~/.quiltrc
COPY . debian/
RUN rm -rf debian/.cache  # undo the .cache hack files here

# Build!
RUN DEB_BUILD_OPTIONS=parallel=6 dpkg-buildpackage -us -uc -sa

# TODO: for bonus points, we could run quick tests here;
# for starters dpkg -i tests?

# Write output files (store build args in ENV first).
ENV oscodename=$oscodename osdistshort=$osdistshort \
    upname=$upname upversion=$upversion debversion=$debversion
RUN . /etc/os-release && fullversion=${upversion}-${debversion}+${osdistshort}${VERSION_ID} && \
    mkdir -p /dist/${upname}_${fullversion} && \
    mv /build/*${fullversion}* /dist/${upname}_${fullversion}/ && \
    mv /build/${upname}_${upversion}.orig.tar.gz /dist/${upname}_${fullversion}/ && \
    cd / && find dist/${upname}_${fullversion} -type f >&2
