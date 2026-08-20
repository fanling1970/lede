#!/bin/bash
# diy-part2.sh

echo "=== 开始 diy-part2.sh ==="

# ======================================
# 强制使用 lisaac 的 Lua 版 Dockerman
# ======================================
echo "--- 处理 Dockerman ---"

# 1. 先卸载可能已经从官方 luci 装上的 JS 版
./scripts/feeds uninstall luci-app-dockerman 2>/dev/null || true

# 2. 从 lisaac 源安装（用包名，不是路径）
./scripts/feeds install -p dockerman luci-app-dockerman

# 3. 验证
echo "--- 验证安装来源 ---"
if [ -d "package/feeds/dockerman/luci-app-dockerman" ]; then
    echo "✅ lisaac Lua 版已安装"
    # 检查是否是 Lua 版（看有没有 luasrc 目录）
    if [ -d "package/feeds/dockerman/luci-app-dockerman/luasrc" ]; then
        echo "✅ 确认是 Lua 版（存在 luasrc 目录）"
    else
        echo "⚠️ 警告：安装的不是 Lua 版，可能没有 luasrc 目录"
    fi
else
    echo "❌ 安装失败"
fi

# 4. 清理并写入配置
sed -i '/CONFIG_PACKAGE_luci-app-dockerman/d' .config
sed -i '/CONFIG_PACKAGE_luci-lib-docker/d' .config

cat >> .config << 'DOCKEREOF'
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_docker-compose=y
CONFIG_PACKAGE_ttyd=y
DOCKEREOF

echo "✅ Dockerman 配置已写入"

# ======================================
# 其余原有配置（无线、Rust 等）
# ======================================

# 修改 hostname
sed -i "s/hostname='.*'/hostname='immortalwrt'/g" package/base-files/files/bin/config_generate

# 修改网关
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

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

# 修复重启补丁
echo "--- 修复 jdCloud ax6600 无限重启 ---"
rm -rf package/kernel/mac80211/patches/nss/ath11k/999-900-bss-transition-handling.patch
echo "✅ 已删除可能导致重启的补丁"

# 修复 Rust（修正 404 问题）
echo "--- 修复 Rust 编译问题 ---"
if [ -f "feeds/packages/lang/rust/Makefile" ]; then
    # 使用正确的 URL（去掉 refs/heads）
    wget -O feeds/packages/lang/rust/Makefile https://raw.githubusercontent.com/aimetu/OpenWrt-Actions/main/patches/Makefile 2>/dev/null || {
        echo "⚠️ Rust Makefile 下载失败，使用现有文件"
    }
    if [ -f "feeds/packages/lang/rust/Makefile" ]; then
        sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile
        echo "✅ Rust Makefile 已更新"
    fi
else
    echo "⚠️ Rust Makefile 不存在，跳过"
fi

# 添加无线状态检查脚本（修复目录不存在问题）
echo "--- 添加无线状态检查脚本 ---"
mkdir -p package/base-files/files/usr/bin
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

# 屏蔽 shadowsocks-rust
sed -i '/CONFIG_PACKAGE_shadowsocks-rust/d' .config
echo "# CONFIG_PACKAGE_shadowsocks-rust is not set" >> .config
rm -rf feeds/packages/net/shadowsocks-rust

echo "=== diy-part2.sh 执行完成 ==="
