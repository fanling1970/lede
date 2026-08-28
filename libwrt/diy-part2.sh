#!/bin/bash
# diy-part2.sh - 在 feeds install 之后执行 (libwrt 源码适配版)
echo "=== [DIY-P2] 开始配置第三方包和系统设置 ==="

# ======================================
# 1. 克隆第三方包（不在 feeds 中的包）
# ======================================
echo "--- 克隆 Argon 主题 ---"
rm -rf package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon || {
    echo "❌ Argon 主题拉取失败"
    exit 1
}

echo "--- 克隆 Argon 配置插件 ---"
rm -rf package/luci-app-argon-config
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config || {
    echo "❌ Argon 配置插件拉取失败"
    exit 1
}
echo "✅ Argon 主题克隆完成"

echo "--- 克隆 Athena LED 控制插件 ---"
rm -rf package/luci-app-athena-led
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led || {
    echo "❌ Athena LED 插件拉取失败"
    exit 1
}
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led 2>/dev/null || true
chmod +x package/luci-app-athena-led/root/usr/sbin/athena-led 2>/dev/null || true
echo "✅ Athena LED 插件克隆完成"

# ======================================
# 2. 基础系统设置修改
# ======================================
echo "--- 修改基础系统设置 ---"

# 修改主机名（libwrt 此文件存在）
sed -i "s/hostname='.*'/hostname='LibWrt'/g" package/base-files/files/bin/config_generate

# 修改默认网关 IP（libwrt 默认 192.168.1.1 → 192.168.100.1）
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

# 注：libwrt 源码无 package/lean 目录，zzz-default-settings 相关操作已移除
# libwrt 默认密码即为 none（空密码），无需额外清除

echo "✅ 基础系统设置修改完成"

# ======================================
# 3. 清理冲突包（保留源码自带 OpenClash）
# ======================================
echo "--- 清理冲突包 ---"

rm -rf feeds/luci/applications/luci-app-istorex 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-quickstart 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-store 2>/dev/null || true
rm -rf feeds/luci/libraries/luci-lib-taskd 2>/dev/null || true
rm -rf feeds/luci/applications/quickstart 2>/dev/null || true

echo "✅ 冲突包清理完成（保留源码 OpenClash）"

# ======================================
# 4. 更新并安装特定 feeds
# ======================================
echo "--- 更新 feeds ---"
./scripts/feeds update helloworld istore nas nas_luci

echo "--- 安装 feeds ---"
./scripts/feeds install -a -p helloworld
./scripts/feeds install -d y -p istore luci-app-store
./scripts/feeds install -a -p nas
./scripts/feeds install -a -p nas_luci
echo "✅ feeds 安装完成"

# ======================================
# 5. 无线网络配置
# ======================================
echo "--- 配置无线网络 ---"
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-wireless << 'WIFIEOF'
#!/bin/sh

# JDC_AX6600 无线配置
# radio0: 5G (内置 SoC WiFi)
uci set wireless.radio0.channel='149'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='HE80'
uci set wireless.default_radio0.ssid='JDC_AX6600_5G'
uci set wireless.default_radio0.key='BUZHIDAOWA'
uci set wireless.default_radio0.encryption='psk2'

# radio1: 2.4G (内置 SoC WiFi 第二个频段)
uci set wireless.radio1.channel='6'
uci set wireless.radio1.band='2g'
uci set wireless.radio1.htmode='HT40'
uci set wireless.default_radio1.ssid='JDC_AX6600_2.4G'
uci set wireless.default_radio1.key='BUZHIDAOWA'
uci set wireless.default_radio1.encryption='psk2'

# radio2: 5G (PCIe 外置网卡)
uci set wireless.radio2.channel='44'
uci set wireless.radio2.band='5g'
uci set wireless.radio2.htmode='HE160'
uci set wireless.default_radio2.ssid='JDC_AX6600_5G2'
uci set wireless.default_radio2.key='BUZHIDAOWA'
uci set wireless.default_radio2.encryption='psk2'

uci commit wireless
exit 0
WIFIEOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-wireless
echo "✅ 无线配置完成"

# ======================================
# 6. 验证配置
# ======================================
echo "=== 验证 feeds 安装状态 ==="
ls -la package/ | grep -E "(argon|athena)" || echo "（无）"
echo "=== 验证 feeds 源 ==="
grep -E "(helloworld|istore|nas)" feeds.conf.default || echo "（无）"
echo "=== 检查 OpenClash ==="
if [ -d "feeds/luci/applications/luci-app-openclash" ]; then
    echo "✅ 源码自带 OpenClash 存在"
else
    echo "⚠️ 源码自带 OpenClash 不存在，将在下次编译时恢复"
fi

# ======================================
# 7. Docker 根目录配置（首次启动生效）
# ======================================
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-docker-data << 'EOF'
#!/bin/sh
mkdir -p /mnt/mmcblk0p27/docker
if uci get dockerd.globals >/dev/null 2>&1; then
    uci set dockerd.globals.data_root="/mnt/mmcblk0p27/docker"
else
    uci set dockerd.@globals[0].data_root="/mnt/mmcblk0p27/docker"
fi
uci commit dockerd
/etc/init.d/cron enable 2>/dev/null
exit 0
EOF
chmod 755 package/base-files/files/etc/uci-defaults/99-docker-data

# ======================================================
# Docker防火墙hotplug方案A：仅持久化写入uci，不触碰运行时防火墙
# 保证首次开机LuCI网页一定可用，规避fw4与dockerd iptables‑nft冲突
# ======================================================
echo "--- 部署docker防火墙hotplug脚本 ---"
mkdir -p files/etc/hotplug.d/net
cat > files/etc/hotplug.d/net/90-docker-br-attach << 'DOCKER_FW_EOF'
#!/bin/sh

do_fw_setup() {
    local retry=0
    while [ $retry -lt 3 ]; do
        if uci show firewall.docker >/dev/null 2>&1; then
            break
        fi

        uci add firewall zone
        uci rename firewall.@zone[-1]="docker"

        uci set firewall.docker.name='docker'
        uci set firewall.docker.input='ACCEPT'
        uci set firewall.docker.output='ACCEPT'
        uci set firewall.docker.forward='ACCEPT'
        uci set firewall.docker.masq='1'

        uci del firewall.docker.network
        uci set firewall.docker.device='docker0'
        uci add_list firewall.docker.device='br-+'

        if ! uci show firewall.fwd_docker_wan >/dev/null 2>&1; then
            uci add firewall forwarding
            uci rename firewall.@forwarding[-1]="fwd_docker_wan"
            uci set firewall.fwd_docker_wan.src="docker"
            uci set firewall.fwd_docker_wan.dest="wan"
        fi

        if ! uci show firewall.fwd_lan_docker >/dev/null 2>&1; then
            uci add firewall forwarding
            uci rename firewall.@forwarding[-1]="fwd_lan_docker"
            uci set firewall.fwd_lan_docker.src="lan"
            uci set firewall.fwd_lan_docker.dest="docker"
        fi

        uci commit firewall
        logger -t docker_fw "docker防火墙uci配置已持久写入磁盘，不刷新运行时防火墙"

        if uci show firewall.docker >/dev/null 2>&1; then
            return 0
        fi
        retry=$((retry+1))
        sleep 1
    done
    logger -t docker_fw "docker防火墙uci写入结束"
}

case "$ACTION" in
add)
    if [ "$INTERFACE" = "docker0" ]; then
        logger -t docker_fw "hotplug捕获docker0 add事件"
        sleep 1
        do_fw_setup
    fi
;;
remove)
;;
esac

if [ "x$1" = "xrun" ]; then
    do_fw_setup
fi
DOCKER_FW_EOF
chmod 755 files/etc/hotplug.d/net/90-docker-br-attach

# 兜底脚本：防止hotplug丢失docker0 add事件，后台仅做uci写入，不操作防火墙运行时
mkdir -p files/etc/rc.d
cat > files/etc/rc.d/S99dockerfw << 'EOF'
#!/bin/sh
(
    sleep 12
    if [ -d /sys/class/net/docker0 ]; then
        /etc/hotplug.d/net/90-docker-br-attach run
    fi
) &
EOF
chmod 755 files/etc/rc.d/S99dockerfw

# ===== CPU 温度/架构双行脚本（刷机首次启动时自动创建） =====
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-cpuinfo << 'EOF'
#!/bin/sh
cat > /sbin/cpuinfo << 'SCRIPT'
#!/bin/sh
grep -m1 "Processor" /proc/cpuinfo | sed 's/^Processor[[:space:]]*:[[:space:]]*//'
TEMP_PATH="/sys/class/thermal/thermal_zone0/temp"
if [ -r "$TEMP_PATH" ]; then
    raw_temp=$(cat "$TEMP_PATH")
    temp_int=$(( raw_temp / 1000 ))
    temp_dec=$(( (raw_temp / 100) % 10 ))
    echo "CPU ${temp_int}.${temp_dec}°C"
else
    echo "CPU 0.0°C"
fi
SCRIPT
chmod 755 /sbin/cpuinfo
exit 0
EOF
chmod 755 package/base-files/files/etc/uci-defaults/99-cpuinfo

echo "✅ [DIY-P2] 所有配置完成"
