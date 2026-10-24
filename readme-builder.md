# builder —— arm64 离线构建环境镜像 (Kylin V10 SP1 / aarch64)

供银河麒麟 V10 SP1 (aarch64) 离线物理机使用的**编译沙箱**: 物理机把源码目录挂载进
容器编译，物理机本身无需安装任何编译器。仓库总索引见 [readme.md](readme.md)，
通用打包方法见
[kylin-v10-sp1-aarch64-docker-instructions.md](kylin-v10-sp1-aarch64-docker-instructions.md)
(§7 为本镜像这类"构建环境型"包的变体说明)。

## 为什么基座是 ubuntu:20.04

**基座 glibc ≤ 宿主 glibc，产物才能直接跑在宿主机**——这是构建环境型镜像的核心选型规则:

- 麒麟桌面 V10 SP1 的 glibc 为 2.31，ubuntu:20.04 恰为 2.31 → 容器内编译的 C 产物
  无缝跑宿主；选 22.04+(glibc 2.35)产物会报 `GLIBC_2.34' not found`；
- 产物只在容器内运行时无此限制，可换新基座换新工具链(workflow 的 `base_image` 参数)；
- C++ 产物另受 libstdc++ 影响: 宿主报 libstdc++ 版本错误时加
  `-static-libstdc++ -static-libgcc` 或回容器内运行；
- focal 的 git 2.25 无 safe.directory 检查(git 2.35.2 引入)，挂载目录不存在
  dubious ownership 报错；换更新基座需 `git config --system --add safe.directory '*'`。

## 镜像内容(1.1.0)

| 类别 | 内容 |
|---|---|
| 编译器 | gcc/g++ 9.4、gcc-10/g++-10(并存，`CC/CXX` 可切)、clang 10、gfortran、nasm |
| 构建系统 | cmake、ninja、meson、pkg-config、autoconf/automake/autoconf-archive/libtool/m4、flex/bison、gettext、swig、texinfo |
| 调试 | gdb、valgrind、strace、ltrace、ccache |
| 语言 | python3 + pip + venv + setuptools/wheel(含 dev 头文件) |
| 开发库 | openssl、zlib、bzip2/lzma/zstd/lz4、readline/ncurses、sqlite3、libffi、gdbm、libxml2/xslt/expat、pcre/pcre2、yaml、curl、libevent、libuv、icu、libarchive、sodium、seccomp/cap/attr/acl、uuid、numa、json-c/jsoncpp/jansson、boost 常用模块、eigen3、fmt、spdlog、protobuf、gtest/benchmark、dbus/glib2、jpeg/png/gif/tiff/webp/freetype |
| 版本控制 | git、svn、mercurial |
| 传输/归档 | curl、wget、rsync、ssh 客户端、zip/unzip、7z、zstd/lz4 |
| 其他 | man 手册页、locales(已生成 zh_CN.UTF-8 / en_US.UTF-8) |

具体版本以包内 `MANIFEST.txt` 的容器内实查为准。

## 构建

- Actions → **Build arm64 offline builder image (Kylin V10 SP1)**，参数:
  `builder_version`(镜像版本)、`base_image`(基座)、`extra_packages`(追加 apt 包，空格分隔)、
  `publish_release`；
- push 改动 `builder/**` 或 workflow 自动构建。**push 触发时 dispatch inputs 为空**，
  版本取 workflow 脚本里的兜底值——改默认版本要 input default 和兜底值两处同步
  (踩过坑: 兜底没同步导致扩充镜像以 1.0.0 标签出包并覆盖旧资产，见手册 §5 第 9 条)；
- 产物: `builder-offline-arm64-<版本>.tar.gz` = 单镜像 `builder:<版本>` +
  `README.txt` + `MANIFEST.txt`，导入即 `docker load`。

## 版本历史

- **1.1.0**(2026-10-24): 扩充离线依赖——40+ 开发库、gcc-10/clang/gfortran、meson、
  python3-venv、valgrind/strace/ltrace、svn/hg/rsync、zh_CN locale 等。**当前推荐版本**。
- 1.0.0(2026-10-24): 初版(最小工具链，177.7 MiB)。其 release 资产后被 1.0.0 标签的
  扩充构建覆盖(版本号兜底 bug)，内容与 1.1.0 相同但版本号不实——**勿用 1.0.0**；
  如需还原历史初版，在 Actions 手动 dispatch 选择 commit `a0f1d81` 重跑。

## 离线机使用(摘要)

```bash
docker load -i images/builder-offline-images-arm64.tar
# 编译当前目录:
docker run --rm -v "$PWD":/src -w /src builder:<版本> bash -c "./configure && make -j$(nproc)"
# 交互式:
docker run --rm -it -v "$PWD":/src -w /src builder:<版本> bash
# 以宿主用户身份(产物不属 root):
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/src -w /src builder:<版本> make
```

前提: aarch64、内核 4.19+、Docker 20.10+、磁盘余量 ≥ 镜像体积×2。
完整说明(FAQ/删除镜像等)以包内 `README.txt` 为准。

## 完全离线构建的边界

镜像只覆盖 apt 可装的部分，以下依赖须在**有网侧**预先准备、随源码一起拷入:

1. 语言生态的第三方包不走 apt，需 vendor 进源码树:
   - pip: 有网机 `pip download -r requirements.txt -d vendor/wheels/`，
     离线机 `pip install --no-index --find-links=vendor/wheels/ -r requirements.txt`
   - cargo: 有网机 `cargo vendor vendor/`(按提示写 .cargo/config.toml)
   - go: 有网机 `go mod vendor`，离线机 `go build -mod=vendor`(镜像内无 go)
   - npm: 有网机 `npm ci` 后把 `node_modules` 一起拷过去
2. git 子模块、外部源码包(./autogen 拉取的 tarball 等)需有网侧下载齐；
3. 编译麒麟宿主内核模块: 需要**麒麟的**内核头文件(宿主 4.19.90-*.ky10)，
   ubuntu 头文件不匹配，把麒麟 /usr/src 或 kernel-headers 包拷入容器使用；
4. 缺大件不改 Dockerfile 也可用 `extra_packages` 重新出包，配方:
   Qt5 `qtbase5-dev qtdeclarative5-dev qttools5-dev-tools` / GTK3 `libgtk-3-dev` /
   X11 `libx11-dev libxext-dev libxrender-dev libxrandr-dev libxi-dev` /
   Java 11 `openjdk-11-jdk-headless` / RPM 打包 `rpm` / 文档 `doxygen` /
   x86_64 交叉 `gcc-x86-64-linux-gnu g++-x86-64-linux-gnu`。
