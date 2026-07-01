#!/bin/bash
echo "🔧 DIY Part 2: 编译前自定义操作（拉取插件与修改默认配置）"
echo "执行时间: $(date)"

# ==========================================
# 1. 添加自定义插件源码
# ==========================================
echo "开始拉取自定义插件..."

# 添加 Argon 主题及其配置插件 (适配 Lean LEDE 的 18.06 分支)
# rm -rf package/lean/luci-theme-argon
# git clone -b 18.06 https://github.com/jerrykuku/luci-theme-argon.git package/lean/luci-theme-argon
# git clone https://github.com/jerrykuku/luci-app-argon-config.git package/lean/luci-app-argon-config

# 添加 kenzok8 插件库（包含 SSR Plus+ 和 MosDNS）
git clone --depth=1 https://github.com/kenzok8/openwrt-packages.git package/kenzok8
git clone --depth=1 https://github.com/kenzok8/small.git package/small

echo "✅ 插件源码拉取完成"

# ==========================================
# 2. 修改固件默认配置（IP、密码、WiFi）
# ==========================================
echo "开始修改默认配置..."

# 设置默认 IP 地址为 192.168.100.1
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

# 设置 WiFi 名称 (SSID) 为 JDC_AX6600，密码为 12345678
# 替换默认的 SSID
sed -i 's/OpenWrt/JDC_AX6600/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
# 替换默认的加密方式和密码 (将原本的 disabled=1 关闭，并设置 psk2 密码)
sed -i '/set wireless.default_radio${devidx}.encryption=psk2/!b;n;c\		set wireless.default_radio${devidx}.key=12345678' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i 's/set wireless.default_radio${devidx}.disabled=1/set wireless.default_radio${devidx}.disabled=0/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 设置默认密码为空（Lean 源码默认 root 密码为空，这里做双重保险）
# 确保 /etc/shadow 中 root 用户的密码字段为空
sed -i 's/root:[^:]*:/root::/g' package/base-files/files/etc/shadow 2>/dev/null || true

echo "✅ 默认配置修改完成"

# ==========================================
# 3. 其他自定义操作
# ==========================================
# 例如：修改固件信息
# sed -i 's/OpenWrt/JDC-AX6600-OpenWrt/g' package/base-files/files/etc/banner

echo "✅ DIY Part 2 全部完成"
