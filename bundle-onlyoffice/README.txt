ONLYOFFICE 在线协同编辑离线部署包 (银河麒麟 V10 SP1 / aarch64)
================================================================

这是什么
  局域网多用户在线协同编辑 docx/xlsx/pptx 的全套离线栈:
    nginx(80 唯一入口) + nextcloud(用户/文件/共享) + documentserver(协同编辑内核)
    + postgres + redis
  编辑内核与 MS Office 格式兼容度高，公文字体挂载后可保留排版。
  所有镜像为 arm64，导入后运行全程零外网。

包内容
  images/onlyoffice-docs-images-arm64.tar   documentserver 协同编辑内核
  images/suite-images-arm64.tar             nextcloud + postgres + redis + nginx
  apps/onlyoffice-*.tar.gz                  nextcloud 协同连接器(离线安装用)
  docker-compose.yml                        编排文件
  nginx/conf.d/default.conf                 入口反代配置(/ 与 /ds-vpath/)
  env.example                               配置模板(安装时自动复制为 .env)
  install.sh                                一键导入、启动并配置协同
  uninstall.sh                              停止/卸载(数据默认保留)
  MANIFEST.txt                              组件版本、来源与摘要

前提条件
  1) aarch64 机器，内核 4.19+(麒麟 V10 SP1 满足)
  2) 已安装并启动 Docker(20.10+)，且有 docker compose 插件或 docker-compose 命令
     麒麟源安装: sudo yum install docker-engine docker-compose
  3) 内存 8GB 以上(编辑内核峰值吃内存)；磁盘余量 12GB 以上
  4) 80 端口未被占用(与 teable 包共存无冲突，teable 用 3000)

部署步骤(在有 docker 权限的用户下执行)
  1. 分包下载时先合并: cat onlyoffice-offline-*.tar.gz.part-* > bundle.tar.gz
  2. tar -xzf bundle.tar.gz && cd onlyoffice-offline
  3. (可选但建议) vim env.example 预先改好密码；密码请用纯字母数字
     不改也行: install.sh 会自动生成随机密码并记录在 .env
  4. bash install.sh
  5. 浏览器访问 http://<本机IP> ，用 .env 中的管理员账号登录
  6. 验证协同: 管理员 -> 设置 -> ONLYOFFICE -> 连接状态应为『正常』;
     上传一个 docx 打开，另一账号同时打开同一文件即多人实时协同

公文字体(保留排版的关键)
  默认只读挂载宿主机两个目录进编辑内核:
    /usr/share/fonts/winfonts   (建议放 仿宋_GB2312.ttf / 楷体_GB2312.ttf 等)
    /usr/share/fonts            (整目录以 /usr/share/fonts/kylin 只读可见)
  追加字体放 ./data/fonts (容器内 /usr/share/fonts/custom)。
  拷入字体后执行:
    docker compose exec documentserver fc-cache -fv
    docker compose exec documentserver fc-list | grep 仿宋_GB2312
  (旧版 docker-compose 命令把 "docker compose" 换成 "docker-compose"，下同)

常用命令(在本目录执行)
  查看状态   docker ps
  查看日志   docker compose logs -f documentserver / nextcloud / nginx
  重启       docker compose restart
  停止       docker compose stop
  卸载       bash uninstall.sh          (保留数据)
  彻底清除   bash uninstall.sh --purge  (删除全部数据卷，./data 需手动删)

数据位置
  docker 卷 docs-db     nextcloud 数据库(用户/分享关系，最重要)
  docker 卷 nextcloud   nextcloud 程序与配置
  ./data/nextcloud-data 用户上传的全部文件(直接落盘在包目录)
  ./data/custom-apps    协同连接器
  ./data/fonts          追加公文字体
  docker 卷 docs-data/docs-lib/docs-log   编辑内核数据/缓存/日志
  数据库备份: docker compose exec docs-db pg_dump -U nextcloud nextcloud > backup.sql

升级到新版本
  下载新版本离线包 → 覆盖解压 → bash install.sh
  (重新导入镜像并按 .env 版本重建容器，数据卷不受影响; 升级前先备份数据库与
   ./data/nextcloud-data)

常见问题
  - documentserver 反复重启/内部 PostgreSQL 起不来:
    老版本 docker(20.10.x) 的默认 seccomp 会拦截容器内数据库的系统调用，
    本包已在 docker-compose.yml 为 documentserver 配置 seccomp=unconfined
    (ONLYOFFICE 官方麒麟指南同款解法); 若仍有问题，升级 docker 到 23+
  - 局域网无法访问: 放行防火墙
      firewall-cmd --add-port=80/tcp --permanent && firewall-cmd --reload
  - 服务器换了 IP: 改 .env 的 SERVER_IP 后重跑 bash install.sh
  - 协同光标不动/编辑器打不开: 多为浏览器到服务器的 websocket 被掐，
    确认直接访问 http://IP 而非经其他代理; 查看 nginx 配置
    /ds-vpath/ 的 Upgrade/Connection 头是否还在
  - 端口 80 被占: 改 .env 的 APP_PORT 后 docker compose up -d，
    并重跑 bash install.sh 让连接器地址带上新端口
  - 重启服务器后自启: compose 已配 restart: always，docker 服务开机自启即可
