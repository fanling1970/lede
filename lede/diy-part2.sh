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

# ========== 更新并安装 feeds ==========
./scripts/feeds update -a
./scripts/feeds install -a
