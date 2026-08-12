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
# Docker 自动化配置（修正版，适配IPQ60xx）
# ======================================
echo "--- 植入Docker自动挂载与防火墙修复脚本 ---"

# 1. 优化Docker数据盘挂载（等待分区就绪，避免启动顺序问题）
mkdir -p files/etc/init.d
cat > files/etc/init.d/docker-mount << 'EOF'
#!/bin/sh /etc/rc.common
START=19  # 比dockerd（99）早启动，确保挂载完成
STOP=15

boot() {
    # 最多等30秒，确保分区识别完成
    for i in $(seq 1 30); do
        # 已经挂载则直接返回
        if mountpoint -q /mnt/mmcblk0p27; then
            echo "Docker: /mnt/mmcblk0p27 已挂载"
            mkdir -p /mnt/mmcblk0p27/docker
            chmod 755 /mnt/mmcblk0p27/docker
            return 0
        fi
        # 按UUID查找分区
        DEVICE=$(blkid -U "1a99b9cc-fa4a-4f08-a4e0-5523f260d532")
        if [ -n "$DEVICE" ]; then
            echo "Docker: 挂载 $DEVICE 到 /mnt/mmcblk0p27"
            mount -t ext4 "$DEVICE" /mnt/mmcblk0p27
            if mountpoint -q /mnt/mmcblk0p27; then
                mkdir -p /mnt/mmcblk0p27/docker
                chmod 755 /mnt/mmcblk0p27/docker
                echo "Docker: 挂载成功"
                return 0
            fi
        fi
        sleep 1
    done
    echo "Docker: 挂载 /mnt/mmcblk0p27 失败，使用默认目录"
    mkdir -p /opt/docker
}
EOF
chmod +x files/etc/init.d/docker-mount

# 2. 固化Docker核心配置（网段+镜像源，保持不变）
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

# 3. 固化Dockerman配置（避免覆盖docker根目录）
mkdir -p files/etc/config
cat > files/etc/config/dockerman << 'EOF'
config dockerman 'dockerman'
    option socket_path '/var/run/docker.sock'
    option status_path '/tmp/.docker_action_status'
    option debug 'false'
    option remote_endpoint '0'
    list ac_allowed_interface 'br-lan'
EOF

# 4. 【关键修正】把防火墙脚本放到正确的hotplug目录（net事件）
# Docker创建docker0/br-*时会触发net事件，这个脚本才会执行
mkdir -p files/etc/hotplug.d/net
cat > files/etc/hotplug.d/net/00-docker-firewall << 'EOF'
#!/bin/sh

# 只处理网络接口添加事件
[ "$ACTION" = "add" ] || exit 0

# 只处理Docker相关的接口（docker0或br-开头的网桥）
case "$INTERFACE" in
    docker0|br-*)
        ;;
    *)
        exit 0
        ;;
esac

echo "Docker firewall: 检测到接口 $INTERFACE，开始配置防火墙"

# 等待接口完全初始化
sleep 2

# 如果docker zone不存在，先创建（兼容luci-app-dockerman未创建的情况）
if ! uci -q get firewall.docker >/dev/null; then
    echo "Docker firewall: 创建docker zone"
    uci add firewall zone
    uci set firewall.@zone[-1].name='docker'
    uci set firewall.@zone[-1].input='ACCEPT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='ACCEPT'
    uci set firewall.@zone[-1].masq='1'
    uci set firewall.@zone[-1].mtu_fix='1'
fi

# 获取docker zone的配置节点
ZONE=$(uci show firewall | grep "option name='docker'" | head -n1 | cut -d'.' -f2 | cut -d'=' -f1)

# 添加docker0和br-+到zone，避免重复
for dev in docker0 br-+; do
    if ! uci get firewall.$ZONE.device 2>/dev/null | grep -q "$dev"; then
        uci add_list firewall.$ZONE.device="$dev"
        echo "Docker firewall: 添加 $dev 到docker zone"
    fi
done

# 添加转发规则：LAN访问Docker，Docker访问WAN
if ! uci show firewall | grep -q "option src='lan'.*option dest='docker'"; then
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest='docker'
    echo "Docker firewall: 添加LAN->Docker转发规则"
fi

if ! uci show firewall | grep -q "option src='docker'.*option dest='wan'"; then
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='docker'
    uci set firewall.@forwarding[-1].dest='wan'
    echo "Docker firewall: 添加Docker->WAN转发规则"
fi

uci commit firewall
/etc/init.d/firewall reload
echo "Docker firewall: 配置完成"
EOF
chmod +x files/etc/hotplug.d/net/00-docker-firewall

# 删除之前放错目录的旧脚本
rm -rf files/etc/hotplug.d/docker

echo "✅ Docker固化脚本植入完成"

