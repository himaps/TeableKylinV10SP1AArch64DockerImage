# arm64 离线构建环境 —— 银河麒麟 V10 SP1 物理机用
# 基座选 ubuntu:20.04 的原因: 其 glibc 恰为 2.31，与麒麟 V10 SP1 桌面版一致，
# 容器内编译出的 C/C++ 产物可直接在宿主机运行(选 22.04+ 则产物会因宿主
# glibc 过旧报 `GLIBC_2.34' not found 跑不起来)。
# 注意: focal 的 git 2.25 无 safe.directory 检查(git 2.35.2 才引入)，不存在
#       dubious ownership 报错；若换更新基座，需在镜像里
#       git config --system --add safe.directory '*'。
#
# 离线机无法 apt 补装，本文件按"常用依赖尽量装全"组织；大件(Qt5/JDK/X11 等)
# 不默认打入，走 workflow 的 extra_packages 参数(配方见 README.txt)。
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

RUN ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

ARG EXTRA_PACKAGES=""
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      gcc-10 g++-10 gfortran clang nasm \
      make cmake ninja-build meson pkg-config \
      autoconf automake autoconf-archive libtool libltdl-dev m4 \
      flex bison texinfo gettext swig \
      gdb valgrind strace ltrace ccache \
      man-db manpages-dev file less vim procps \
      git subversion mercurial curl wget rsync openssh-client ca-certificates \
      unzip zip tar bzip2 xz-utils zstd lz4 p7zip-full gzip \
      python3 python3-pip python3-dev python3-venv python3-setuptools python3-wheel \
      libssl-dev zlib1g-dev libbz2-dev liblzma-dev libzstd-dev liblz4-dev \
      libreadline-dev libncurses-dev libsqlite3-dev libffi-dev libgdbm-dev \
      libxml2-dev libxslt1-dev libexpat1-dev libpcre2-dev libpcre3-dev libyaml-dev \
      libcurl4-openssl-dev libevent-dev libuv1-dev libicu-dev \
      libarchive-dev libsodium-dev libseccomp-dev libcap-dev libattr1-dev libacl1-dev \
      uuid-dev libnuma-dev \
      libjson-c-dev libjsoncpp-dev libjansson-dev \
      libboost-dev libboost-system-dev libboost-filesystem-dev libboost-thread-dev \
      libboost-regex-dev libboost-program-options-dev libboost-chrono-dev \
      libboost-date-time-dev libboost-test-dev \
      libeigen3-dev libfmt-dev libspdlog-dev \
      protobuf-compiler libprotobuf-dev \
      libgtest-dev libbenchmark-dev \
      libdbus-1-dev libglib2.0-dev \
      libjpeg-dev libpng-dev libgif-dev libtiff-dev libwebp-dev libfreetype6-dev \
      locales \
      $EXTRA_PACKAGES \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *zh_CN.UTF-8/zh_CN.UTF-8/; s/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen \
    && locale-gen

CMD ["/bin/bash"]
