#!/bin/bash
# diy-part2.sh

# ========== 基础设置修改 ==========
# 修改 device 设备名称（保留）
sed -i "s/hostname='.*'/hostname='LEDE'/g" package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='LEDE'/g" package/base-files/luci2/bin/config_generate

# 加入作者信息（保留）
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g" package/lean/default-settings/files/zzz-default-settings   
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By J.Y'/g" package/lean/default-settings/files/zzz-default-settings

sed -i "2iuci set istore.istore.channel='OpenWrt'" package/lean/default-settings/files/zzz-default-settings
sed -i "3iuci commit istore" package/lean/default-settings/files/zzz-default-settings

# 默认网关 ip 地址修改（保留）
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/luci2/bin/config_generate

# 修改 wifi 无线名称（删除或注释掉这行）
# sed -i "s/LEDE/JDC_AX6600/g" package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 清除默认密码 password（保留）
sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings

# ========== 添加无线网络配置 ==========
cat >> package/lean/default-settings/files/zzz-default-settings << 'EOF'

# 设置无线网络 - radio0 (5G)
uci set wireless.radio0.channel='149'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='HE80'
uci set wireless.@wifi-iface[0].ssid='JDC_AX6600_5G'
uci set wireless.@wifi-iface[0].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[0].encryption='psk2'

# 设置无线网络 - radio1 (2.4G)
uci set wireless.radio1.channel='6'
uci set wireless.radio1.band='2g'
uci set wireless.radio1.htmode='HT40'
uci set wireless.@wifi-iface[1].ssid='JDC_AX6600_2.4G'
uci set wireless.@wifi-iface[1].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[1].encryption='psk2'

# 设置无线网络 - radio2 (5G2)
uci set wireless.radio2.channel='44'
uci set wireless.radio2.band='5g'
uci set wireless.radio2.htmode='HE160'
uci set wireless.@wifi-iface[2].ssid='JDC_AX6600_5G2'
uci set wireless.@wifi-iface[2].key='BUZHIDAOWA'
uci set wireless.@wifi-iface[2].encryption='psk2'

# 提交无线配置更改
uci commit wireless
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

# kenzok8/openwrt-packages（取需要的包和依赖）
git clone --depth=1 https://github.com/kenzok8/openwrt-packages.git /tmp/kenzok8-packages

# 复制主包
cp -r /tmp/kenzok8-packages/luci-app-istorex package/
cp -r /tmp/kenzok8-packages/luci-app-quickstart package/
cp -r /tmp/kenzok8-packages/luci-app-store package/

# 复制缺失的依赖包（关键！）
cp -r /tmp/kenzok8-packages/luci-lib-taskd package/
cp -r /tmp/kenzok8-packages/quickstart package/
cp -r /tmp/kenzok8-packages/luci-lib-xterm package/
cp -r /tmp/kenzok8-packages/taskd package/

# 检查是否有其他依赖
if [ -d "/tmp/kenzok8-packages/luci-lib-docker" ]; then
    cp -r /tmp/kenzok8-packages/luci-lib-docker package/
fi

rm -rf /tmp/kenzok8-packages
