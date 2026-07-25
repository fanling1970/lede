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
# Docker 防火墙兼容性终极修复方案（纯 nftables 注入 + 清理残留）
# ======================================
echo "--- 集成 Docker 防火墙终极修复（纯 nftables 注入版） ---"

# 清理所有旧的 uci-defaults 和 rc.local 中的 UCI 相关逻辑
rm -f package/base-files/files/etc/uci-defaults/97-docker-zone-preseed
rm -f package/base-files/files/etc/uci-defaults/98-docker-fw4-fix
rm -f package/base-files/files/etc/uci-defaults/98-docker-firewall-fix

mkdir -p files/etc
cat > files/etc/rc.local << 'RCEOF'
#!/bin/sh

(
    # === 阶段1：等待 docker0 和 dockerd 完全就绪 ===
    for i in $(seq 1 90); do
        if ip link show docker0 &>/dev/null && pgrep -x dockerd >/dev/null; then
            break
        fi
        sleep 1
    done

    # 额外等待 dockerd 完成 nftables 链创建
    sleep 12
    logger -t docker-fix "docker0 and dockerd ready, starting nft check"

    # === 阶段2：验证并注入 nftables jump 规则（绝不触发 firewall reload）===
    NFT_JUMP_OK=""
    if nft list chain inet fw4 forward 2>/dev/null | grep -q 'iifname "docker0".*jump forward_docker'; then
        NFT_JUMP_OK="1"
    fi

    if [ -z "$NFT_JUMP_OK" ]; then
        # 确保 forward_docker 链存在
        if ! nft list chain inet fw4 forward_docker &>/dev/null; then
            nft add chain inet fw4 forward_docker '{ type filter hook forward priority filter; policy accept; }' 2>/dev/null
            logger -t docker-fix "Created missing nft chain forward_docker"
        fi

        # 注入 jump 规则（幂等）
        nft insert rule inet fw4 forward iifname "docker0" jump forward_docker comment "!fw4: Handle docker IPv4/IPv6 forward traffic" 2>/dev/null
        logger -t docker-fix "Injected nft jump rule to forward_docker"

        # 确保基础 FORWARD 放行
        if ! nft list chain inet fw4 forward 2>/dev/null | grep -q 'iifname "docker0".*accept'; then
            nft insert rule inet fw4 forward iifname "docker0" accept 2>/dev/null
        fi
        if ! nft list chain inet fw4 forward 2>/dev/null | grep -q 'oifname "docker0".*ct state'; then
            nft insert rule inet fw4 forward oifname "docker0" ct state established,related accept 2>/dev/null
        fi

        # 确保 NAT 链存在
        if ! nft list chain inet fw4 srcnat_docker &>/dev/null; then
            nft add chain inet fw4 srcnat_docker '{ type nat hook postrouting priority srcnat; policy accept; }' 2>/dev/null
            nft add rule inet fw4 srcnat_docker oifname != "docker0" masquerade 2>/dev/null
            logger -t docker-fix "Created nft srcnat_docker chain with masquerade"
        fi
    else
        logger -t docker-fix "nft jump rule already present, no injection needed"
    fi

    # === 阶段3：清理所有 UCI 中的 docker zone/forwarding 残留（防止 LuCI 显示异常）===
    CHANGED=0
    for idx in $(seq 30 -1 0); do
        zname=$(uci -q get firewall.@zone[$idx].name 2>/dev/null)
        if [ "$zname" = "docker" ]; then
            uci delete firewall.@zone[$idx]
            CHANGED=1
            logger -t docker-fix "Removed stale UCI zone_docker at index $idx"
        fi
    done
    for idx in $(seq 30 -1 0); do
        src=$(uci -q get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci -q get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
            CHANGED=1
            logger -t docker-fix "Removed stale UCI forwarding involving docker at index $idx"
        fi
    done
    if [ "$CHANGED" -eq 1 ]; then
        uci commit firewall
        # 注意：这里不执行 firewall reload！避免冲刷刚注入的 nft 规则
        # 仅提交 UCI 以清除 LuCI 界面残留，nftables 状态保持不变
        logger -t docker-fix "Committed UCI cleanup (no reload to preserve nft rules)"
    fi

    # === 阶段4：最终验证 ===
    if nft list chain inet fw4 forward 2>/dev/null | grep -q 'iifname "docker0".*jump forward_docker'; then
        logger -t docker-fix "✅ FINAL: nftables docker rules VERIFIED OK"
    else
        logger -t docker-fix "❌ FINAL: nftables docker rules STILL MISSING!"
    fi

    logger -t docker-fix "=== Docker fw4 pure-nft fix completed ==="
) &

exit 0
RCEOF
chmod +x files/etc/rc.local

echo "✅ Docker 防火墙终极修复已集成（纯 nftables 注入 + UCI 残留清理 + 零 reload）"

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
