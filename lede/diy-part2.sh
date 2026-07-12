#!/bin/bash
# diy-part2.sh - 在 feeds install 之后执行

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

# 修改 wifi 无线名称
sed -i "s/LEDE/JDC_AX6600/g" package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 清除默认密码 password
sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings

# ========== 克隆第三方包 ==========
# 自定义 argon 主题
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config

# jdCloud ax6600 led screen ctrl
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led

# kenzok8/small（含 SSR、OpenClash 等）
git clone --depth=1 https://github.com/kenzok8/small.git package/small

# kenzok8/openwrt-packages（只取需要的三个包）
git clone --depth=1 https://github.com/kenzok8/openwrt-packages.git /tmp/kenzok8-packages
cp -r /tmp/kenzok8-packages/luci-app-istorex package/
cp -r /tmp/kenzok8-packages/luci-app-quickstart package/
cp -r /tmp/kenzok8-packages/luci-app-store package/
rm -rf /tmp/kenzok8-packages

# ========== 删除冲突包（在 feeds install 之后，但必须手动删除 feeds 安装的冲突包）==========
# 删除 feeds 安装的冲突包（因为 feeds install 已经执行过了）
rm -rf package/feeds/luci/luci-app-openclash 2>/dev/null || true
rm -rf package/feeds/luci/luci-theme-argon 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-istorex 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-quickstart 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-store 2>/dev/null || true

# 删除 feeds 安装的其他可能冲突包
rm -rf package/feeds/packages/shadowsocks-libev 2>/dev/null || true
rm -rf package/feeds/packages/shadowsocksr-libev 2>/dev/null || true
rm -rf package/feeds/packages/xray-core 2>/dev/null || true
rm -rf package/feeds/packages/v2ray-core 2>/dev/null || true
rm -rf package/feeds/packages/sing-box 2>/dev/null || true
