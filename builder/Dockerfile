# arm64 离线构建环境 —— 银河麒麟 V10 SP1 物理机用
# 基座选 ubuntu:20.04 的原因: 其 glibc 恰为 2.31，与麒麟 V10 SP1 桌面版一致，
# 容器内编译出的 C/C++ 产物可直接在宿主机运行(选 22.04+ 则产物会因宿主
# glibc 过旧报 `GLIBC_2.34' not found 跑不起来)。
# 注意: focal 的 git 2.25 无 safe.directory 检查(git 2.35.2 才引入)，不存在
#       dubious ownership 报错；若换更新基座，需在镜像里
#       git config --system --add safe.directory '*'。
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

RUN ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 编译工具链 + 常用开发库。离线机无法后期 apt 补装，需要新包时改这里，
# 或不改文件直接走 workflow 的 extra_packages 参数。
ARG EXTRA_PACKAGES=""
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      cmake ninja-build pkg-config \
      autoconf automake libtool flex bison \
      git curl wget ca-certificates \
      unzip zip tar bzip2 xz-utils file \
      python3 python3-pip python3-dev \
      gdb ccache \
      libssl-dev zlib1g-dev \
      vim less \
      $EXTRA_PACKAGES \
    && rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]
