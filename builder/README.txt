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
  3) 磁盘余量 = 镜像体积 × 2 以上

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
  编译器   gcc/g++ 9.4 与 gcc-10/g++-10 并存(CC/CXX 可切)、clang 10、gfortran 9
  构建系统 cmake、ninja、meson、pkg-config、autoconf/automake/autoconf-archive/
           libtool/m4、flex/bison、gettext、swig、texinfo
  调试     gdb、valgrind、strace、ltrace、ccache
  语言     python3 + pip + venv + setuptools/wheel(含 dev 头文件)
  开发库   openssl、zlib、bzip2/lzma/zstd/lz4、readline/ncurses、sqlite3、libffi、
           gdbm、libxml2/libxslt/expat、pcre/pcre2、yaml、curl、libevent、libuv、
           icu、libarchive、sodium、seccomp/cap/attr/acl、uuid、numa、
           json-c/jsoncpp/jansson、boost(常用模块)、eigen3、fmt、spdlog、
           protobuf、gtest/benchmark、dbus/glib2、jpeg/png/gif/tiff/webp/freetype
  版本控制 git、svn、mercurial
  传输/归档 curl、wget、rsync、ssh 客户端、zip/unzip、7z、zstd/lz4
  其他     nasm、man 手册页、 locales(已生成 zh_CN.UTF-8 / en_US.UTF-8)

在宿主机运行编译产物(重要)
  本镜像基座 glibc 与麒麟 V10 SP1 桌面版同为 2.31，C 产物可直接在宿主机运行。
  C++ 产物依赖镜像内 libstdc++，若宿主报 libstdc++ 版本错误，两种办法:
    1) 编译时加 -static-libstdc++ -static-libgcc(静态链接，产物体积变大);
    2) 产物继续放回本镜像内运行。

完全离线构建的边界(重要)
  镜像只覆盖 apt 可装的部分。以下依赖须在"有网侧"预先准备、随源码一起拷入:
  1) 语言生态的第三方包不走 apt，需 vendor 进源码树后再拷到离线机:
     - pip:      有网机器 pip download -r requirements.txt -d vendor/wheels/
                 离线机 pip install --no-index --find-links=vendor/wheels/ -r requirements.txt
     - cargo:    有网机器 cargo vendor vendor/ (按提示写 .cargo/config.toml)
     - go:       有网机器 go mod vendor，离线机 go build -mod=vendor
                 (镜像内无 go，需要 go 请扩包或要求打入官方 tarball)
     - npm:      有网机器 npm ci(把 node_modules 一起拷过去)
  2) git 子模块、外部源码包(./autogen 拉取的 tarball 等)需有网侧下载齐。
  3) 编译麒麟宿主内核模块: 需要 **麒麟的**内核头文件(宿主 4.19.90-*.ky10)，
     ubuntu 头文件不匹配。把麒麟 /usr/src 或 kernel-headers 包挂载/拷入容器使用。
  4) 缺大件按需重新出包(改 Dockerfile 或用 workflow 的 extra_packages 参数):
     Qt5:        qtbase5-dev qtdeclarative5-dev qttools5-dev-tools
     GTK3:       libgtk-3-dev
     X11 基础:   libx11-dev libxext-dev libxrender-dev libxrandr-dev libxi-dev
     Java 11:    openjdk-11-jdk-headless
     RPM 打包:   rpm
     文档:       doxygen
     x86_64 交叉: gcc-x86-64-linux-gnu g++-x86-64-linux-gnu
     (版本对不上时告诉我，可把官方 tarball 打进镜像重新出包)

常见问题
  - 产物文件属于 root: 用上面 -u "$(id -u):$(id -g)" 方式运行
  - 缺依赖库/工具: 离线机无法 apt 安装，需在构建端改 Dockerfile 或用
    workflow 的 extra_packages 参数重新出包
  - 删除镜像: docker rmi builder:<版本>
