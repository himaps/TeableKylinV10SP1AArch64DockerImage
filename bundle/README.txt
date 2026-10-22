Teable 离线部署包 (银河麒麟 V10 SP1 / aarch64)
================================================

包内容
  images/teable-offline-images-arm64.tar   三个镜像: teable + postgres + redis
  docker-compose.yml                       编排文件
  env.example                              配置模板(安装时自动复制为 .env)
  install.sh                               一键导入并启动
  uninstall.sh                             停止/卸载(数据默认保留)
  MANIFEST.txt                             组件版本、来源与摘要

前提条件
  1) aarch64 机器，内核 4.19+(麒麟 V10 SP1 满足)
  2) 已安装并启动 Docker(20.10+)，且有 docker compose 插件或 docker-compose 命令
     麒麟源安装: sudo yum install docker-engine docker-compose
  3) 磁盘余量 3GB 以上

部署步骤(在有 docker 权限的用户下执行)
  1. tar -xzf teable-offline-arm64-*.tar.gz
  2. cd teable-offline
  3. (可选但建议) vim env.example 修改 CHANGE_ME 密码
     密码请用纯字母数字，勿含 $ 等特殊字符
  4. bash install.sh
  5. 浏览器访问 http://<本机IP>:3000 注册管理员

常用命令(在本目录执行，COMPOSE 为 docker compose 或 docker-compose)
  查看状态   docker ps
  查看日志   docker compose logs -f teable
  重启       docker compose restart
  停止       docker compose stop
  卸载       bash uninstall.sh          (保留数据)
  彻底清除   bash uninstall.sh --purge  (删除全部数据卷)

数据位置(docker 卷，可用 docker volume inspect 查看)
  teable-db      数据库全部业务数据(最重要)
  teable-data    应用附件
  teable-cache   redis 持久化

升级到新版本
  下载新版本离线包 → 覆盖解压 → bash install.sh
  (会重新导入镜像并以新镜像重建容器，数据卷不受影响；升级前建议
   docker exec teable-db pg_dump -U teable teable > backup.sql 备份数据库)

常见问题
  - 无 docker 权限: sudo bash install.sh，或 usermod -aG docker <用户> 后重新登录
  - 端口被占用: 改 .env 的 APP_PORT 后 docker compose up -d
  - 局域网无法访问: .env 的 PUBLIC_ORIGIN 改为 http://<内网IP>:3000，
    并放行防火墙: firewall-cmd --add-port=3000/tcp --permanent && firewall-cmd --reload
  - 启动失败: docker compose logs teable / docker compose logs teable-db 看日志
