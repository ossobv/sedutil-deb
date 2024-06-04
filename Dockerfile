ARG osdistro=ubuntu
ARG oscodename=jammy

FROM $osdistro:$oscodename
LABEL maintainer="Walter Doekes <wjdoekes+sedutil@osso.nl>"
LABEL dockerfile-vcs=https://github.com/ossobv/sedutil-deb

ARG DEBIAN_FRONTEND=noninteractive

# This time no "keeping the build small". We only use this container for
# building/testing and not for running, so we can keep files like apt
# cache. We do this before copying anything and before getting lots of
# ARGs from the user. That keeps this bit cached.
RUN echo 'APT::Install-Recommends "0";' >/etc/apt/apt.conf.d/01norecommends
# We'll be ignoring "debconf: delaying package configuration, since apt-utils
#   is not installed"
RUN apt-get update -q && \
    apt-get dist-upgrade -y && \
    apt-get install -y \
        ca-certificates curl \
        build-essential devscripts dh-autoreconf dpkg-dev equivs quilt && \
    printf "%s\n" \
        QUILT_PATCHES=debian/patches QUILT_NO_DIFF_INDEX=1 \
        QUILT_NO_DIFF_TIMESTAMPS=1 'QUILT_DIFF_OPTS="--show-c-function"' \
        'QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"' \
        >~/.quiltrc

# Apt-get prerequisites according to control file.
COPY control /build/debian/control
RUN mk-build-deps --install --remove --tool "apt-get -y" /build/debian/control

# ubuntu, ubu, jammy, sedutil, 1.15.1, '', 0osso1
ARG osdistro osdistshort oscodename upname upversion debepoch= debversion

COPY changelog /build/debian/changelog
RUN . /etc/os-release && \
    sed -i -e "1s/+[^+)]*)/+${osdistshort}${VERSION_ID})/;1s/) stable;/) ${oscodename};/" \
        /build/debian/changelog && \
    fullversion="${upversion}-${debversion}+${osdistshort}${VERSION_ID}" && \
    expected="${upname} (${debepoch}${fullversion}) ${oscodename}; urgency=medium" && \
    head -n1 /build/debian/changelog && \
    if test "$(head -n1 /build/debian/changelog)" != "${expected}"; \
    then echo "${expected}  <-- mismatch" >&2; false; fi

# Set up upstream source, move debian dir and jump into dir.
#
# Trick to allow caching of SOURCE*.tar.gz files. Download them
# once using the curl command below into .cache/* if you want. The COPY
# is made conditional by the "[z]" "wildcard". (We need one existing
# file (README.rst) so the COPY doesn't fail.)
COPY ./README.rst .cache/${upname}_${upversion}.orig.tar.g[z] /build/
#ARG upsrc_md5=610301fca946d515251c30a4e26bd6a0  # for 1.15.1
ARG upsrc_md5=a3e035ae167936ba9364bb121120b499  # for 1.20.0
RUN if ! test -s /build/${upname}_${upversion}.orig.tar.gz; then \
    url="https://codeload.github.com/Drive-Trust-Alliance/sedutil/tar.gz/${upversion}" && \
    echo "Fetching: ${url}" >&2 && \
    curl --fail "${url}" >/build/${upname}_${upversion}.orig.tar.gz; fi
RUN test $(md5sum /build/${upname}_${upversion}.orig.tar.gz | awk '{print $1}') = ${upsrc_md5}
RUN cd /build && tar zxf "${upname}_${upversion}.orig.tar.gz"
COPY . /build/${upname}-${upversion}/debian/
RUN cp /build/debian/changelog /build/${upname}-${upversion}/debian/changelog && \
    rm -rf /build/${upname}-${upversion}/debian/.cache  # undo the .cache hack files here
WORKDIR /build/${upname}-${upversion}

# Build!
RUN DEB_BUILD_OPTIONS=parallel=6 dpkg-buildpackage -us -uc -sa

# TODO: for bonus points, we could run quick tests here;
# for starters dpkg -i tests?

# Write output files (store build args in ENV first).
ENV oscodename=$oscodename osdistshort=$osdistshort \
    upname=$upname upversion=$upversion debversion=$debversion
RUN . /etc/os-release && fullversion=${upversion}-${debversion}+${osdistshort}${VERSION_ID} && \
    mkdir -p /dist/${upname}_${fullversion} && \
    mv /build/${upname}_${upversion}.orig.tar.gz /dist/${upname}_${fullversion}/ && \
    mv /build/*${fullversion}* /dist/${upname}_${fullversion}/ && \
    cd / && find dist/${upname}_${fullversion} -type f >&2
