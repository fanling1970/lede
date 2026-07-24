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
# Docker 防火墙兼容性终极修复方案（fw4 UCI 精确复刻版）
# ======================================
echo "--- 集成 Docker 防火墙终极修复（fw4 UCI 精确复刻） ---"

mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/98-docker-fw4-fix << 'FWEOF'
#!/bin/sh
# === Docker fw4 防火墙精确修复（仅首次启动执行）===
# 策略：创建与 LuCI 手动添加完全一致的 UCI zone，然后一次性 reload

(
    # 等待 docker0 就绪
    for i in $(seq 1 60); do
        ip link show docker0 &>/dev/null && break
        sleep 1
    done

    # 检查是否已有 docker zone
    HAS_ZONE=""
    for idx in $(seq 0 30); do
        zname=$(uci -q get firewall.@zone[$idx].name 2>/dev/null)
        [ "$zname" = "docker" ] && HAS_ZONE="$idx" && break
    done

    if [ -z "$HAS_ZONE" ]; then
        # 精确复刻 LuCI 手动创建的 docker zone 参数
        uci add firewall zone
        uci set firewall.@zone[-1].name='docker'
        uci set firewall.@zone[-1].network='docker'
        uci set firewall.@zone[-1].input='ACCEPT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].forward='ACCEPT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].conntrack='1'
        uci set firewall.@zone[-1].family='any'
        logger -t docker-fix "Created fw4-compatible zone_docker"
    else
        # 补全可能缺失的参数
        uci set firewall.@zone[$HAS_ZONE].input='ACCEPT'
        uci set firewall.@zone[$HAS_ZONE].output='ACCEPT'
        uci set firewall.@zone[$HAS_ZONE].forward='ACCEPT'
        uci set firewall.@zone[$HAS_ZONE].masq='1'
        uci set firewall.@zone[$HAS_ZONE].mtu_fix='1'
        uci set firewall.@zone[$HAS_ZONE].conntrack='1'
        uci set firewall.@zone[$HAS_ZONE].family='any'
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
    logger -t docker-fix "Docker fw4 UCI fix completed on first boot"
) &

exit 0
FWEOF
chmod +x package/base-files/files/etc/uci-defaults/98-docker-fw4-fix

# rc.local：仅做兜底检查，绝不执行 firewall reload
mkdir -p files/etc
cat > files/etc/rc.local << 'RCEOF'
#!/bin/sh

(
    for i in $(seq 1 60); do
        if ip link show docker0 &>/dev/null; then
            sleep 8

            # 检查 UCI zone 是否存在且完整
            HAS_ZONE=""
            MASQ_OK=""
            for idx in $(seq 0 30); do
                zname=$(uci -q get firewall.@zone[$idx].name 2>/dev/null)
                if [ "$zname" = "docker" ]; then
                    HAS_ZONE="$idx"
                    masq=$(uci -q get firewall.@zone[$idx].masq 2>/dev/null)
                    fwd=$(uci -q get firewall.@zone[$idx].forward 2>/dev/null)
                    [ "$masq" = "1" ] && [ "$fwd" = "ACCEPT" ] && MASQ_OK="1"
                    break
                fi
            done

            if [ -z "$HAS_ZONE" ] || [ -z "$MASQ_OK" ]; then
                # Zone 缺失或不完整，修补后 reload（仅在必要时）
                if [ -z "$HAS_ZONE" ]; then
                    uci add firewall zone
                    uci set firewall.@zone[-1].name='docker'
                    uci set firewall.@zone[-1].network='docker'
                    HAS_ZONE="-1"
                    logger -t docker-fix "rc.local: Created missing zone_docker"
                fi
                uci set firewall.@zone[$HAS_ZONE].input='ACCEPT'
                uci set firewall.@zone[$HAS_ZONE].output='ACCEPT'
                uci set firewall.@zone[$HAS_ZONE].forward='ACCEPT'
                uci set firewall.@zone[$HAS_ZONE].masq='1'
                uci set firewall.@zone[$HAS_ZONE].mtu_fix='1'
                uci set firewall.@zone[$HAS_ZONE].conntrack='1'
                uci set firewall.@zone[$HAS_ZONE].family='any'
                uci commit firewall
                /etc/init.d/firewall reload 2>/dev/null
                logger -t docker-fix "rc.local: Repatched zone_docker and reloaded"
            else
                # Zone 完整，检查 nftables 规则是否存在
                if ! nft list chain inet fw4 forward 2>/dev/null | grep -q 'jump forward_docker'; then
                    # 规则丢失但 UCI 正确，说明 dockerd 未正确绑定，重启 dockerd
                    /etc/init.d/dockerd restart 2>/dev/null
                    logger -t docker-fix "rc.local: Restarted dockerd to bind nft rules"
                else
                    logger -t docker-fix "rc.local: Docker firewall OK, no action needed"
                fi
            fi

            break
        fi
        sleep 1
    done
) &

exit 0
RCEOF
chmod +x files/etc/rc.local

# 清理旧版无效脚本
rm -f package/base-files/files/etc/uci-defaults/97-docker-zone-preseed

echo "✅ Docker 防火墙终极修复已集成（fw4 UCI 精确复刻 + 智能兜底）"

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
