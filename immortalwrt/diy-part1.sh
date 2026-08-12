#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# ======================================
# Docker 自动化配置 - 固化启动脚本
# ======================================
echo "--- 植入 Docker 自动挂载与防火墙修复脚本 ---"

# 1. 创建 docker-mount 服务：负责开机挂载分区
mkdir -p files/etc/init.d
cat > files/etc/init.d/docker-mount << 'EOF'
#!/bin/sh /etc/rc.common
START=19
STOP=15

boot() {
    # 等待系统初始化完成
    sleep 5
    
    # 检查是否已挂载
    if ! mountpoint -q /mnt/mmcblk0p27; then
        DEVICE=$(blkid -U "1a99b9cc-fa4a-4f08-a4e0-5523f260d532")
        if [ -n "$DEVICE" ]; then
            echo "Docker: Mounting $DEVICE to /mnt/mmcblk0p27"
            mount -t ext4 "$DEVICE" /mnt/mmcblk0p27
            mkdir -p /mnt/mmcblk0p27/docker
            chmod 755 /mnt/mmcblk0p27/docker
        else
            echo "Docker: UUID 1a99b9cc... not found!"
        fi
    fi
}
EOF
chmod +x files/etc/init.d/docker-mount

# 2. 创建 daemon.json 模板（编译时固化）
mkdir -p files/etc/docker
cat > files/etc/docker/daemon.json << 'EOF'
{
  "data-root": "/mnt/mmcblk0p27/docker/",
  "log-level": "warn",
  "registry-mirrors": [
    "https://registry.linkease.net:5443"
  ],
  "iptables": true,
  "bip": "192.168.200.1/24",
  "default-address-pools": [
    { "base": "192.168.201.0/16", "size": 24 }
  ]
}
EOF

# 3. 创建 Hotplug 脚本：Docker 启动时自动重载防火墙（解决首次启动无 docker 区域问题）
mkdir -p files/etc/hotplug.d/docker
cat > files/etc/hotplug.d/docker/00-reload-firewall << 'EOF'
#!/bin/sh
# 当 Docker 服务状态改变时触发
[ "$ACTION" = "start" ] && {
    logger -t "docker-hotplug" "Docker started, reloading firewall..."
    # 短暂延迟确保 docker0 网卡已创建
    sleep 2
    /etc/init.d/firewall reload
}
EOF
chmod +x files/etc/hotplug.d/docker/00-reload-firewall

echo "✅ Docker 固化脚本植入完成"
