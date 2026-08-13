# ------------------------------
# 1. Docker 根目录固化（启动自动修正+兜底，适配刷机场景）
# ------------------------------
echo "--- 固化 Docker 根目录自动修正脚本 ---"
mkdir -p files/etc/rc.d
cat > files/etc/rc.d/S19docker-link << 'EOF'
#!/bin/sh /etc/rc.common
START=19  # 比 dockerd（99）早启动，确保软链接先就绪
boot() {
    # 1. 检查外置存储是否已自动挂载（你的老固件已经支持自动挂载，这里做容错）
    if [ ! -d "/mnt/mmcblk0p27" ]; then
        logger -t docker-link "错误：/mnt/mmcblk0p27 未挂载，Docker 将使用默认目录"
        return 1
    fi

    # 2. 确保外置目录存在
    mkdir -p /mnt/mmcblk0p27/docker

    # 3. 处理 /opt/docker 软链接（避免重复操作，修正错误链接）
    if [ ! -L "/opt/docker" ]; then
        # 情况1：/opt/docker 是默认目录（非软链接），且有数据，先迁移到外置盘
        if [ -d "/opt/docker" ] && [ -n "$(ls -A /opt/docker 2>/dev/null)" ]; then
            logger -t docker-link "迁移默认目录数据到外置存储..."
            cp -a /opt/docker/* /mnt/mmcblk0p27/docker/ 2>/dev/null
            rm -rf /opt/docker
        fi
        # 创建软链接
        ln -sf /mnt/mmcblk0p27/docker /opt/docker
        logger -t docker-link "Docker 根目录软链接已创建：/opt/docker → /mnt/mmcblk0p27/docker"
    else
        # 情况2：/opt/docker 已是软链接，检查目标是否正确
        CURRENT_TARGET=$(readlink /opt/docker)
        if [ "$CURRENT_TARGET" != "/mnt/mmcblk0p27/docker" ]; then
            rm -f /opt/docker
            ln -sf /mnt/mmcblk0p27/docker /opt/docker
            logger -t docker-link "Docker 软链接目标已修正为 /mnt/mmcblk0p27/docker"
        else
            logger -t docker-link "Docker 软链接已正确配置，无需操作"
        fi
    fi

    # 4. 兜底校验 daemon.json 配置（防止手动改过配置导致冲突）
    if [ -f "/etc/docker/daemon.json" ]; then
        CURRENT_DATA_ROOT=$(grep '"data-root"' /etc/docker/daemon.json | cut -d'"' -f4)
        if [ "$CURRENT_DATA_ROOT" != "/mnt/mmcblk0p27/docker" ]; then
            sed -i 's|"data-root":.*|"data-root": "/mnt/mmcblk0p27/docker",|' /etc/docker/daemon.json
            logger -t docker-link "已修正 daemon.json 中的 data-root 配置"
        fi
    fi

    # 5. 最终校验，输出结果到系统日志，方便排查问题
    if [ -d "/opt/docker" ] && [ "$(readlink /opt/docker)" = "/mnt/mmcblk0p27/docker" ]; then
        logger -t docker-link "Docker 根目录固化成功，最终路径：/mnt/mmcblk0p27/docker"
    else
        logger -t docker-link "Docker 根目录固化失败，请检查外置存储挂载状态"
    fi
}
EOF
chmod +x files/etc/rc.d/S19docker-link

# 固化 Docker 配置
mkdir -p files/etc/docker
cat > files/etc/docker/daemon.json << 'EOF'
{
  "data-root": "/mnt/mmcblk0p27/docker/",
  "log-level": "warn",
  "registry-mirrors": ["https://registry.linkease.net:5443"],
  "iptables": true,
  "bip": "192.168.200.1/24",
  "default-address-pools": [{ "base": "192.168.201.0/16", "size": 24 }]
}
EOF

# 固化防火墙配置
uci -q delete firewall.docker.network
uci add_list firewall.docker.device='docker0'
uci add_list firewall.docker.device='br-+'

