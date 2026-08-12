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

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
# echo 'src-git helloworld https://github.com/fw876/helloworld.git' >>feeds.conf.default
# echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall.git' >>feeds.conf.default
# echo 'src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2.git' >>feeds.conf.default
# echo "src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main" >> "feeds.conf.default"
# echo "src-git neko https://github.com/nosignals/openwrt-neko.git;dev" >> "feeds.conf.default"
# echo "src-git nekobox https://github.com/Thaolga/openwrt-nekobox.git;main" >> "feeds.conf.default"
# echo "src-git mosdns https://github.com/sbwml/luci-app-mosdns.git;v5" >> "feeds.conf.default"
# echo "src-git openclash https://github.com/vernesong/OpenClash.git;dev" >> "feeds.conf.default"
# echo 'src-git nas https://github.com/linkease/nas-packages.git;master' >> feeds.conf.default
# echo 'src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' >> feeds.conf.default

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

# 2. 创建 daemon.json 模板（编译时固化，控制网段）
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

# 3. 【关键】Docker 防火墙兜底：防止重启后出现多个 docker zone
# 逻辑：让 Docker 自己生成 zone，我们只负责“多了就删”
mkdir -p files/etc/hotplug.d/docker
cat > files/etc/hotplug.d/docker/00-firewall-dedup << 'EOF'
#!/bin/sh

# 只在 Docker 服务启动时执行
[ "$ACTION" = "start" ] || exit 0

# 等 Docker 完全建立 docker0 / br-*
sleep 2

DOCKER_ZONES=$(uci show firewall | grep "option name='docker'" | wc -l)

if [ "$DOCKER_ZONES" -gt 1 ]; then
    echo "检测到 $DOCKER_ZONES 个 docker zone，正在清理..."

    # 保留第一个 docker zone，删除其余的
    FIRST=$(uci show firewall | grep "option name='docker'" | head -n1 | cut -d'[' -f2 | cut -d']' -f1)

    uci show firewall | grep "option name='docker'" | tail -n +2 | while read line; do
        SEC=$(echo "$line" | cut -d'[' -f2 | cut -d']' -f1)
        uci delete firewall.@zone[$SEC]
    done

    uci commit firewall
    /etc/init.d/firewall reload
    echo "docker zone 已清理，仅保留一个"
else
    echo "docker zone 数量正常（$DOCKER_ZONES），无需处理"
fi

# 确保 docker0 / br-+ 在 device 列表中（防止 Compose 网络被墙）
ZONE=$(uci show firewall | grep "option name='docker'" | head -n1 | cut -d'.' -f2 | cut -d'=' -f1)
uci del_list firewall.$ZONE.device='docker0' 2>/dev/null
uci del_list firewall.$ZONE.device='br-+' 2>/dev/null
uci add_list firewall.$ZONE.device='docker0'
uci add_list firewall.$ZONE.device='br-+'
uci commit firewall
EOF
chmod +x files/etc/hotplug.d/docker/00-firewall-dedup

echo "✅ Docker 固化脚本植入完成"
