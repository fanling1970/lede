#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 修改 device 设备名称
sed -i "s/hostname='.*'/hostname='immortalwrt'/g" package/base-files/files/bin/config_generate

# 默认网关 ip 地址修改
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

# ======================================
# Docker 防火墙兼容性终极修复方案（源码级拦截+统一接管）
# ======================================
echo "--- 集成 Docker 防火墙终极修复（源码级拦截双Zone） ---"

# 【核心】从源码层面禁止 dockerd/luci-app-dockerman 自动创建 firewall zone
# 这样无论重启多少次，都只会存在我们手动创建的那一个 zone
echo ">>> Patching dockerd init script to disable auto zone creation..."
if [ -f package/base-files/files/etc/init.d/dockerd ]; then
    # 注释掉所有涉及 uci add/set firewall zone 的行
    sed -i '/uci\s\+add\s\+firewall\s\+zone/s/^/#DISABLED# /' package/base-files/files/etc/init.d/dockerd
    sed -i '/uci\s\+set\s\+firewall\.@zone/s/^/#DISABLED# /' package/base-files/files/etc/init.d/dockerd
    sed -i '/uci\s\+commit\s\+firewall/s/^/#DISABLED# /' package/base-files/files/etc/init.d/dockerd
    echo "✅ Patched package/base-files/files/etc/init.d/dockerd"
fi

# 同时检查 feeds 中的 dockerd 和 luci-app-dockerman
for init_script in \
    feeds/packages/utils/dockerd/files/dockerd.init \
    feeds/luci/applications/luci-app-dockerman/root/etc/init.d/dockerd \
    package/luci-app-dockerman/root/etc/init.d/dockerd; do
    if [ -f "$init_script" ]; then
        sed -i '/uci\s\+add\s\+firewall\s\+zone/s/^/#DISABLED# /' "$init_script"
        sed -i '/uci\s\+set\s\+firewall\.@zone/s/^/#DISABLED# /' "$init_script"
        sed -i '/uci\s\+commit\s\+firewall/s/^/#DISABLED# /' "$init_script"
        echo "✅ Patched $init_script"
    fi
done

mkdir -p package/base-files/files/etc/uci-defaults

# 1. 首次启动：统一创建完整 Zone + Forwarding + NAT保护
cat > package/base-files/files/etc/uci-defaults/98-docker-firewall-fix << 'FWEOF'
#!/bin/sh
# === Docker 防火墙统一接管（仅首次启动执行） ===
# 由于已禁用 dockerd 自动创建 zone，此处负责一次性创建完整配置

(
    # 等待 docker0 就绪
    for i in $(seq 1 60); do
        ip link show docker0 &>/dev/null && break
        sleep 1
    done

    # 检查是否已有 docker zone（防止重复）
    HAS_ZONE=""
    for idx in $(seq 0 30); do
        zname=$(uci -q get firewall.@zone[$idx].name 2>/dev/null)
        [ "$zname" = "docker" ] && HAS_ZONE="$idx" && break
    done

    if [ -z "$HAS_ZONE" ]; then
        uci add firewall zone
        uci set firewall.@zone[-1].name='docker'
        uci set firewall.@zone[-1].network='docker'
        uci set firewall.@zone[-1].input='ACCEPT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].forward='ACCEPT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].conntrack='1'
        logger -t docker-fix "Created unified firewall zone_docker"
    else
        # 即使存在也确保参数完整
        uci set firewall.@zone[$HAS_ZONE].input='ACCEPT'
        uci set firewall.@zone[$HAS_ZONE].output='ACCEPT'
        uci set firewall.@zone[$HAS_ZONE].forward='ACCEPT'
        uci set firewall.@zone[$HAS_ZONE].masq='1'
        uci set firewall.@zone[$HAS_ZONE].mtu_fix='1'
        uci set firewall.@zone[$HAS_ZONE].conntrack='1'
        logger -t docker-fix "Patched existing zone_docker at index $HAS_ZONE"
    fi

    # 确保 docker -> wan forwarding
    HAS_FWD=""
    for idx in $(seq 0 30); do
        src=$(uci -q get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci -q get firewall.@forwarding[$idx].dest 2>/dev/null)
        [ "$src" = "docker" ] && [ "$dest" = "wan" ] && HAS_FWD="1" && break
    done
    if [ -z "$HAS_FWD" ]; then
        uci add firewall forwarding
        uci set firewall.@forwarding[-1].src='docker'
        uci set firewall.@forwarding[-1].dest='wan'
        logger -t docker-fix "Added docker->wan forwarding rule"
    fi

    uci commit firewall
    /etc/init.d/firewall reload 2>/dev/null

    # NAT链保护（幂等写入）
    if ! grep -q "Docker NAT chain protection" /etc/firewall.user 2>/dev/null; then
        cat >> /etc/firewall.user << 'USEREOF'

# Docker NAT chain protection
iptables -t nat -N DOCKER 2>/dev/null || true
iptables -t nat -N DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
iptables -t nat -N DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
iptables -t filter -N DOCKER 2>/dev/null || true
iptables -t filter -N DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
iptables -t filter -N DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
USEREOF
        logger -t docker-fix "Appended NAT chain protection to firewall.user"
    fi

    logger -t docker-fix "Docker firewall unified setup completed"
) &

exit 0
FWEOF
chmod +x package/base-files/files/etc/uci-defaults/98-docker-firewall-fix

# 2. rc.local 兜底（每次启动确保 FORWARD 规则 + Zone 完整性）
mkdir -p files/etc
cat > files/etc/rc.local << 'RCEOF'
#!/bin/sh

(
    for i in $(seq 1 45); do
        if ip link show docker0 &>/dev/null; then
            sleep 5
            
            # 兜底：如果 zone 意外丢失则重建
            HAS_ZONE=""
            for idx in $(seq 0 30); do
                zname=$(uci -q get firewall.@zone[$idx].name 2>/dev/null)
                [ "$zname" = "docker" ] && HAS_ZONE="$idx" && break
            done
            if [ -z "$HAS_ZONE" ]; then
                uci add firewall zone
                uci set firewall.@zone[-1].name='docker'
                uci set firewall.@zone[-1].network='docker'
                uci set firewall.@zone[-1].input='ACCEPT'
                uci set firewall.@zone[-1].output='ACCEPT'
                uci set firewall.@zone[-1].forward='ACCEPT'
                uci set firewall.@zone[-1].masq='1'
                uci set firewall.@zone[-1].mtu_fix='1'
                uci set firewall.@zone[-1].conntrack='1'
                uci commit firewall
                logger -t docker-fix "rc.local: Recreated missing zone_docker"
            fi
            
            /etc/init.d/firewall reload 2>/dev/null
            
            # 补全 FORWARD 链
            iptables -C FORWARD -i docker0 -o !docker0 -j ACCEPT 2>/dev/null || \
                iptables -I FORWARD -i docker0 -o !docker0 -j ACCEPT
            iptables -C FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
                iptables -I FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            
            logger -t docker-fix "rc.local: Firewall reloaded & FORWARD rules patched"
            break
        fi
        sleep 1
    done
) &

exit 0
RCEOF
chmod +x files/etc/rc.local
echo "✅ Docker 防火墙终极修复已集成（源码级拦截双Zone + 统一接管）"

# ======================================
# 无线网络配置 - 已验证的LEDE配置
# ======================================
echo "--- 应用已验证的LEDE无线配置 ---"
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-wireless << 'WIFIEOF'
#!/bin/sh

# JDC_AX6600 无线配置 - 从LEDE移植已验证
# 基于实际硬件测试，接口编号和配置已验证有效

# radio0: 5G (内置 SoC WiFi) - 已验证
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.channel='149'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='HE80'
uci set wireless.radio0.country='CN'
uci set wireless.radio0.cell_density='0'
uci set wireless.default_radio0.ssid='JDC_AX6600_5G'
uci set wireless.default_radio0.key='BUZHIDAOWA'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.network='lan'

# radio1: 2.4G (内置 SoC WiFi 第二个频段) - 已验证
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.channel='6'
uci set wireless.radio1.band='2g'
uci set wireless.radio1.htmode='HT40'
uci set wireless.radio1.country='CN'
uci set wireless.radio1.cell_density='0'
uci set wireless.default_radio1.ssid='JDC_AX6600_2.4G'
uci set wireless.default_radio1.key='BUZHIDAOWA'
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.default_radio1.network='lan'

# radio2: 5G (PCIe 外置网卡) - 已验证
uci set wireless.radio2.disabled='0'
uci set wireless.radio2.channel='44'
uci set wireless.radio2.band='5g'
uci set wireless.radio2.htmode='HE160'
uci set wireless.radio2.country='CN'
uci set wireless.radio2.cell_density='0'
uci set wireless.default_radio2.ssid='JDC_AX6600_5G2'
uci set wireless.default_radio2.key='BUZHIDAOWA'
uci set wireless.default_radio2.encryption='psk2'
uci set wireless.default_radio2.network='lan'

uci commit wireless

echo "无线配置已应用：" > /tmp/wireless-setup.log
uci show wireless | grep -E "(radio[0-9]\.(disabled|channel|band|htmode)|default_radio[0-9]\.ssid)" >> /tmp/wireless-setup.log
chmod 600 /etc/config/wireless 2>/dev/null

exit 0
WIFIEOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-wireless
echo "✅ LEDE无线配置已移植"

# 修复 jdCloud ax6600 无限重启
echo "--- 修复 jdCloud ax6600 无限重启 ---"
rm -rf package/kernel/mac80211/patches/nss/ath11k/999-900-bss-transition-handling.patch
echo "✅ 已删除可能导致重启的补丁"

# 修复 rust 报错
echo "--- 修复 Rust 编译问题 ---"
wget -O feeds/packages/lang/rust/Makefile https://raw.githubusercontent.com/aimetu/OpenWrt-Actions/refs/heads/main/patches/Makefile
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile
echo "✅ Rust Makefile 已更新"

# 添加无线状态检查脚本（调试用）
echo "--- 添加无线状态检查脚本 ---"
cat > package/base-files/files/usr/bin/wifi-status << 'STATUSEOF'
#!/bin/sh
echo "=== JDC_AX6600 无线状态检查 ==="
echo "编译时间: $(date)"
echo "固件版本: $(cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_DESCRIPTION | cut -d= -f2)"
echo ""
echo "1. 无线接口列表:"
iwinfo 2>/dev/null | grep -E "ESSID|Mode|Channel" || echo "iwinfo未安装或无线未启动"
echo ""
echo "2. UCI无线配置:"
uci show wireless | grep -v "key=" | grep -v "passphrase="
echo ""
echo "3. 无线物理设备:"
ls -la /sys/class/ieee80211/ 2>/dev/null && {
    for phy in /sys/class/ieee80211/*; do
        echo "设备: $(basename $phy)"
        [ -f $phy/name ] && echo "  名称: $(cat $phy/name)"
        [ -f $phy/macaddress ] && echo "  MAC: $(cat $phy/macaddress)"
    done
}
echo ""
echo "4. 无线网络状态:"
ifconfig | grep -A1 "wlan"
STATUSEOF

chmod +x package/base-files/files/usr/bin/wifi-status
echo "✅ 无线状态检查脚本已添加"

# 彻底屏蔽shadowsocks-rust独立包，避免意外编译报错
sed -i '/CONFIG_PACKAGE_shadowsocks-rust/d' .config
echo "# CONFIG_PACKAGE_shadowsocks-rust is not set" >> .config
rm -rf feeds/packages/net/shadowsocks-rust

echo "=== diy-part2.sh 执行完成（含Docker首次启动修复+LEDE无线配置）==="
