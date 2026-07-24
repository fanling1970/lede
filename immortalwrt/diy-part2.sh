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
# Docker 防火墙兼容性终极修复方案（fw4适配+编译期预置）
# ======================================
echo "--- 集成 Docker 防火墙终极修复（fw4/nftables 适配版） ---"

# 【核心】自动探测并 patch 所有可能的 dockerd init 脚本
echo ">>> Auto-detecting and patching dockerd init scripts..."
DOCKERD_PATCHED=0
for script in \
    package/base-files/files/etc/init.d/dockerd \
    feeds/packages/utils/dockerd/files/dockerd.init \
    feeds/luci/applications/luci-app-dockerman/root/etc/init.d/dockerd \
    package/luci-app-dockerman/root/etc/init.d/dockerd \
    package/utils/dockerd/files/dockerd.init \
    $(find . -path "*/init.d/dockerd" -o -path "*/dockerd.init" 2>/dev/null); do
    if [ -f "$script" ] && ! grep -q "#DISABLED#" "$script"; then
        # 注释掉所有 uci firewall zone 相关操作
        sed -i '/uci[[:space:]]\{1,\}add[[:space:]]\{1,\}firewall[[:space:]]\{1,\}zone/s/^/#DISABLED# /' "$script"
        sed -i '/uci[[:space:]]\{1,\}set[[:space:]]\{1,\}firewall\.@zone/s/^/#DISABLED# /' "$script"
        sed -i '/uci[[:space:]]\{1,\}commit[[:space:]]\{1,\}firewall/s/^/#DISABLED# /' "$script"
        echo "✅ Patched: $script"
        DOCKERD_PATCHED=$((DOCKERD_PATCHED + 1))
    fi
done
if [ "$DOCKERD_PATCHED" -eq 0 ]; then
    echo "⚠️ WARNING: No dockerd init script found to patch! Listing candidates..."
    find . -name "dockerd*" -type f 2>/dev/null | head -20
fi

# 【关键】编译期直接预置正确的 docker zone 到 UCI 默认配置
# 这样刷机后 zone 就存在，无需等待运行时创建
echo ">>> Pre-seeding docker firewall zone into base-files UCI defaults..."
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/97-docker-zone-preseed << 'PRESEEDEOF'
#!/bin/sh
# === 编译期预置 Docker Zone（仅首次启动执行）===
# 检查是否已有 docker zone，没有则创建（兼容 fw3/fw4）
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
    logger -t docker-fix "Pre-seeded firewall zone_docker"
else
    # 确保参数完整
    uci set firewall.@zone[$HAS_ZONE].input='ACCEPT'
    uci set firewall.@zone[$HAS_ZONE].output='ACCEPT'
    uci set firewall.@zone[$HAS_ZONE].forward='ACCEPT'
    uci set firewall.@zone[$HAS_ZONE].masq='1'
    uci set firewall.@zone[$HAS_ZONE].mtu_fix='1'
    uci set firewall.@zone[$HAS_ZONE].conntrack='1'
    logger -t docker-fix "Patched existing zone_docker at index $HAS_ZONE"
fi

# 确保 forwarding
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
logger -t docker-fix "Docker zone preseed completed"
exit 0
PRESEEDEOF
chmod +x package/base-files/files/etc/uci-defaults/97-docker-zone-preseed

# rc.local 兜底（每次启动确保 FORWARD 规则 + Zone 完整性）
mkdir -p files/etc
cat > files/etc/rc.local << 'RCEOF'
#!/bin/sh

(
    for i in $(seq 1 45); do
        if ip link show docker0 &>/dev/null; then
            sleep 5
            
            # 兜底：如果 zone 丢失则重建
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
            
            # fw3 iptables 兜底
            if command -v iptables &>/dev/null; then
                iptables -C FORWARD -i docker0 -o !docker0 -j ACCEPT 2>/dev/null || \
                    iptables -I FORWARD -i docker0 -o !docker0 -j ACCEPT
                iptables -C FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
                    iptables -I FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            fi
            
            # fw4 nftables 兜底
            if command -v nft &>/dev/null; then
                nft list chain inet fw4 forward | grep -q "docker0" || {
                    nft insert rule inet fw4 forward iifname "docker0" accept 2>/dev/null
                    nft insert rule inet fw4 forward oifname "docker0" ct state established,related accept 2>/dev/null
                }
            fi
            
            logger -t docker-fix "rc.local: Firewall reloaded & FORWARD rules patched"
            break
        fi
        sleep 1
    done
) &

exit 0
RCEOF
chmod +x files/etc/rc.local
echo "✅ Docker 防火墙终极修复已集成（fw4适配+编译期预置+自动探测patch）"

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
