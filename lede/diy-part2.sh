#!/bin/bash
# diy-part2.sh

# ========== 基础设置修改 ==========
# 修改 device 设备名称
sed -i "s/hostname='.*'/hostname='LEDE'/g" package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='LEDE'/g" package/base-files/luci2/bin/config_generate

# 加入作者信息
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g" package/lean/default-settings/files/zzz-default-settings   
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By J.Y'/g" package/lean/default-settings/files/zzz-default-settings

sed -i "2iuci set istore.istore.channel='OpenWrt'" package/lean/default-settings/files/zzz-default-settings
sed -i "3iuci commit istore" package/lean/default-settings/files/zzz-default-settings

# 默认网关 ip 地址修改
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/luci2/bin/config_generate

# 清除默认密码 password
sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings

# ========== 添加无线网络配置（已验证正确）==========
# 方法1：直接修改 mac80211.sh 模板
cat >> package/kernel/mac80211/files/lib/wifi/mac80211.sh << 'EOF'

# ===== 自定义无线配置（JDC_AX6600）=====
set_wifi_config() {
    # radio0 (5G) - 内置 SoC WiFi
    uci set wireless.radio0.channel='149'
    uci set wireless.radio0.band='5g'
    uci set wireless.radio0.htmode='HE80'
    uci set wireless.default_radio0.ssid='JDC_AX6600_5G'
    uci set wireless.default_radio0.key='BUZHIDAOWA'
    uci set wireless.default_radio0.encryption='psk2'

    # radio1 (2.4G) - 内置 SoC WiFi 第二个频段
    uci set wireless.radio1.channel='6'
    uci set wireless.radio1.band='2g'
    uci set wireless.radio1.htmode='HT40'
    uci set wireless.default_radio1.ssid='JDC_AX6600_2.4G'
    uci set wireless.default_radio1.key='BUZHIDAOWA'
    uci set wireless.default_radio1.encryption='psk2'

    # radio2 (5G) - PCIe 外置网卡
    uci set wireless.radio2.channel='44'
    uci set wireless.radio2.band='5g'
    uci set wireless.radio2.htmode='HE160'
    uci set wireless.default_radio2.ssid='JDC_AX6600_5G2'
    uci set wireless.default_radio2.key='BUZHIDAOWA'
    uci set wireless.default_radio2.encryption='psk2'

    uci commit wireless
    wifi reload
}

# 在无线初始化后执行
set_wifi_config
EOF

# 方法2：创建独立的无线配置脚本
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-wireless << 'EOF'
#!/bin/sh

# 设置无线网络 - 已验证正确的配置
uci set wireless.radio0.channel='149'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='HE80'
uci set wireless.default_radio0.ssid='JDC_AX6600_5G'
uci set wireless.default_radio0.key='BUZHIDAOWA'
uci set wireless.default_radio0.encryption='psk2'

uci set wireless.radio1.channel='6'
uci set wireless.radio1.band='2g'
uci set wireless.radio1.htmode='HT40'
uci set wireless.default_radio1.ssid='JDC_AX6600_2.4G'
uci set wireless.default_radio1.key='BUZHIDAOWA'
uci set wireless.default_radio1.encryption='psk2'

uci set wireless.radio2.channel='44'
uci set wireless.radio2.band='5g'
uci set wireless.radio2.htmode='HE160'
uci set wireless.default_radio2.ssid='JDC_AX6600_5G2'
uci set wireless.default_radio2.key='BUZHIDAOWA'
uci set wireless.default_radio2.encryption='psk2'

uci commit wireless
exit 0
EOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-wireless

# 方法3：保留在 zzz-default-settings 中
cat >> package/lean/default-settings/files/zzz-default-settings << 'EOF'

# 设置无线网络 - 使用正确的接口名称（已验证）
uci set wireless.radio0.channel='149'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='HE80'
uci set wireless.default_radio0.ssid='JDC_AX6600_5G'
uci set wireless.default_radio0.key='BUZHIDAOWA'
uci set wireless.default_radio0.encryption='psk2'

uci set wireless.radio1.channel='6'
uci set wireless.radio1.band='2g'
uci set wireless.radio1.htmode='HT40'
uci set wireless.default_radio1.ssid='JDC_AX6600_2.4G'
uci set wireless.default_radio1.key='BUZHIDAOWA'
uci set wireless.default_radio1.encryption='psk2'

uci set wireless.radio2.channel='44'
uci set wireless.radio2.band='5g'
uci set wireless.radio2.htmode='HE160'
uci set wireless.default_radio2.ssid='JDC_AX6600_5G2'
uci set wireless.default_radio2.key='BUZHIDAOWA'
uci set wireless.default_radio2.encryption='psk2'

uci commit wireless
wifi reload
EOF

# ========== 删除冲突包（必须在 feeds install 之前）==========
# 删除源码自带的 openclash，避免和 kenzok8/small 里的冲突
rm -rf feeds/luci/applications/luci-app-openclash

# 删除 argon 主题（用自定义版本替代）
rm -rf feeds/luci/themes/luci-theme-argon

# 防止 kenzok8/small 中的包与源码 feeds 中的同名包冲突
rm -rf feeds/packages/net/{shadowsocks-libev,shadowsocksr-libev,xray-core,v2ray-core,sing-box}

# 如果源码自带 istorex/quickstart/store，也先删除避免冲突
rm -rf feeds/luci/applications/luci-app-istorex
rm -rf feeds/luci/applications/luci-app-quickstart
rm -rf feeds/luci/applications/luci-app-store

# 删除 feeds 中的依赖包，避免冲突
rm -rf feeds/luci/libraries/luci-lib-taskd
rm -rf feeds/luci/applications/quickstart

# ========== 克隆第三方包 ==========
# 自定义 argon 主题
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config

# jdCloud ax6600 led screen ctrl
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led

# kenzok8/small（含 SSR、OpenClash 等）
git clone --depth=1 https://github.com/kenzok8/small.git package/small

# 删除 small 中有问题的包
rm -rf package/small/tcping
rm -rf package/small/dae
rm -rf package/small/daed

# kenzok8/openwrt-packages（取需要的包和依赖，排除 dockerman）
git clone --depth=1 https://github.com/kenzok8/openwrt-packages.git /tmp/kenzok8-packages

# 复制主包（排除 dockerman）
cp -r /tmp/kenzok8-packages/luci-app-istorex package/
cp -r /tmp/kenzok8-packages/luci-app-quickstart package/
cp -r /tmp/kenzok8-packages/luci-app-store package/

# 复制缺失的依赖包
cp -r /tmp/kenzok8-packages/luci-lib-taskd package/
cp -r /tmp/kenzok8-packages/quickstart package/
cp -r /tmp/kenzok8-packages/luci-lib-xterm package/
cp -r /tmp/kenzok8-packages/taskd package/

# 特别注意：不复制 dockerman 相关包！
# 让 feeds install 使用 lede 自带的 dockerman
echo "=== 注意：跳过 kenzok8 中的 dockerman 相关包，使用 lede 自带的版本 ==="

rm -rf /tmp/kenzok8-packages

# ========== 修复 dockerman 编译问题 ==========
echo "=== 修复 dockerman 编译问题 ==="

# 1. 检查当前状态
echo "1. 检查当前 dockerman 配置状态"
if grep -q "CONFIG_PACKAGE_luci-app-dockerman" .config; then
    grep "CONFIG_PACKAGE_luci-app-dockerman" .config
else
    echo "未找到 dockerman 配置，手动添加"
    echo "CONFIG_PACKAGE_luci-app-dockerman=y" >> .config
fi

# 2. 确保 dockerman 是内置（y）而不是模块（m）
sed -i 's/CONFIG_PACKAGE_luci-app-dockerman=m/CONFIG_PACKAGE_luci-app-dockerman=y/g' .config 2>/dev/null || true
sed -i 's/# CONFIG_PACKAGE_luci-app-dockerman is not set/CONFIG_PACKAGE_luci-app-dockerman=y/g' .config 2>/dev/null || true

# 3. 添加必要的依赖
for pkg in dockerd docker luci-lib-docker; do
    if ! grep -q "CONFIG_PACKAGE_${pkg}=y" .config; then
        echo "添加依赖包: $pkg"
        echo "CONFIG_PACKAGE_${pkg}=y" >> .config
    fi
done

# 4. 验证修复
echo "4. 验证 dockerman 相关配置:"
grep -E "CONFIG_PACKAGE_(luci-app-dockerman|dockerd|docker|luci-lib-docker)" .config

echo "=== dockerman 修复完成 ==="

# ========== 验证无线配置状态 ==========
echo "=== 验证无线配置状态 ==="
echo "无线配置已添加到三个位置："
echo "1. mac80211.sh（无线初始化时执行）"
echo "2. /etc/uci-defaults/99-custom-wireless（系统启动时执行）"
echo "3. zzz-default-settings（第一次启动时执行）"
echo "=== 配置验证完成 ==="
