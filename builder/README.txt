arm64 离线构建环境 (银河麒麟 V10 SP1 / aarch64)
================================================

用途
  在离线物理机上以容器方式编译软件: 把源码目录挂载进镜像内编译，
  物理机本身无需安装任何编译工具。

包内容
  images/builder-offline-images-arm64.tar   构建环境镜像(单镜像 builder:<版本>)
  MANIFEST.txt                              基座、glibc、工具链版本与摘要

前提条件
  1) aarch64 机器，内核 4.19+(麒麟 V10 SP1 满足)
  2) 已安装并启动 Docker(20.10+)
  3) 磁盘余量 2GB 以上

导入(一次性)
  docker load -i images/builder-offline-images-arm64.tar

常用用法(把当前目录挂到容器 /src 编译)
  在容器内编译当前目录:
    docker run --rm -v "$PWD":/src -w /src builder:<版本> bash -c "./configure && make -j$(nproc)"
  交互式进容器:
    docker run --rm -it -v "$PWD":/src -w /src builder:<版本> bash
  以宿主用户身份编译(避免产物文件属于 root):
    docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/src -w /src builder:<版本> make
  其他目录: 把 -v "$PWD" 换成任意宿主路径即可。

镜像内工具(具体版本以 MANIFEST.txt 实查为准)
  build-essential(gcc/g++ 9.4、make、libc 头文件)、cmake、ninja、pkg-config、
  autoconf/automake/libtool/flex/bison、git、curl/wget、zip/unzip、
  python3 + pip、gdb、ccache、libssl-dev、zlib1g-dev

在宿主机运行编译产物(重要)
  本镜像基座 glibc 与麒麟 V10 SP1 桌面版同为 2.31，C 产物可直接在宿主机运行。
  C++ 产物依赖镜像内 libstdc++，若宿主报 libstdc++ 版本错误，两种办法:
    1) 编译时加 -static-libstdc++ -static-libgcc(静态链接，产物体积变大);
    2) 产物继续放回本镜像内运行。

常见问题
  - 产物文件属于 root: 用上面 -u "$(id -u):$(id -g)" 方式运行
  - 缺依赖库/工具: 离线机无法 apt 安装，需在构建端改 Dockerfile 或用
    workflow 的 extra_packages 参数重新出包
  - 删除镜像: docker rmi builder:<版本>
