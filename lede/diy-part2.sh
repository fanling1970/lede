
#!/bin/bash
# diy-part2.sh - 在 feeds install 之后执行
echo "=== [DIY-P2] 开始配置第三方包和系统设置 ==="

# ======================================
# 1. 克隆第三方包（不在 feeds 中的包）
# ======================================
echo "--- 克隆 Argon 主题 ---"
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon || {
    echo "❌ Argon 主题拉取失败"
    exit 1
}

echo "--- 克隆 Argon 配置插件 ---"
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config || {
    echo "❌ Argon 配置插件拉取失败"
    exit 1
}
echo "✅ Argon 主题克隆完成"

echo "--- 克隆 Athena LED 控制插件 ---"
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led || {
    echo "❌ Athena LED 插件拉取失败"
    exit 1
}
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led
chmod +x package/luci-app-athena-led/root/usr/sbin/athena-led
echo "✅ Athena LED 插件克隆完成"

# ======================================
# 2. 基础系统设置修改
# ======================================
echo "--- 修改基础系统设置 ---"

# 修改主机名
sed -i "s/hostname='.*'/hostname='LEDE'/g" package/base-files/files/bin/config_generate

# 修改版本描述
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g" package/lean/default-settings/files/zzz-default-settings   
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By J.Y'/g" package/lean/default-settings/files/zzz-default-settings

# 修改默认网关 IP
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

# 清除默认密码
sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings

# 添加 iStore 频道信息
sed -i "2iuci set istore.istore.channel='OpenWrt'" package/lean/default-settings/files/zzz-default-settings
sed -i "3iuci commit istore" package/lean/default-settings/files/zzz-default-settings

echo "✅ 基础系统设置修改完成"

# ======================================
# 3. 清理冲突包（修正：保留源码自带 OpenClash）
# ======================================
echo "--- 清理冲突包 ---"

# 注意：注释掉删除源码自带 openclash 的行
# rm -rf feeds/luci/applications/luci-app-openclash 2>/dev/null || true

# 只删除与新源冲突的 iStore 相关包
rm -rf feeds/luci/applications/luci-app-istorex 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-quickstart 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-store 2>/dev/null || true
rm -rf feeds/luci/libraries/luci-lib-taskd 2>/dev/null || true
rm -rf feeds/luci/applications/quickstart 2>/dev/null || true

echo "✅ 冲突包清理完成（保留源码 OpenClash）"

# ======================================
# 4. 更新并安装特定 feeds（确保安装）
# ======================================
echo "--- 更新 feeds ---"
./scripts/feeds update helloworld istore nas nas_luci

echo "--- 安装 feeds ---"
# 安装 helloworld（SSR）
./scripts/feeds install -a -p helloworld

# 安装 iStore
./scripts/feeds install -d y -p istore luci-app-store

# 安装 NAS 插件
./scripts/feeds install -a -p nas
./scripts/feeds install -a -p nas_luci
echo "✅ feeds 安装完成"

# ======================================
# 5. 无线网络配置
# ======================================
echo "--- 配置无线网络 ---"
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-wireless << 'WIFIEOF'
#!/bin/sh

# JDC_AX6600 无线配置 - 已验证正确的接口名称
# radio0: 5G (内置 SoC WiFi)
uci set wireless.radio0.channel='149'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='HE80'
uci set wireless.default_radio0.ssid='JDC_AX6600_5G'
uci set wireless.default_radio0.key='BUZHIDAOWA'
uci set wireless.default_radio0.encryption='psk2'

# radio1: 2.4G (内置 SoC WiFi 第二个频段)
uci set wireless.radio1.channel='6'
uci set wireless.radio1.band='2g'
uci set wireless.radio1.htmode='HT40'
uci set wireless.default_radio1.ssid='JDC_AX6600_2.4G'
uci set wireless.default_radio1.key='BUZHIDAOWA'
uci set wireless.default_radio1.encryption='psk2'

# radio2: 5G (PCIe 外置网卡)
uci set wireless.radio2.channel='44'
uci set wireless.radio2.band='5g'
uci set wireless.radio2.htmode='HE160'
uci set wireless.default_radio2.ssid='JDC_AX6600_5G2'
uci set wireless.default_radio2.key='BUZHIDAOWA'
uci set wireless.default_radio2.encryption='psk2'

uci commit wireless
exit 0
WIFIEOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-wireless
echo "✅ 无线配置完成"

# ====================================================================
# 6. 创建防火墙基础配置（含 Docker 网络支持）
# ====================================================================
echo "配置防火墙基础规则..."

mkdir -p files/etc/config
cat > files/etc/config/firewall << 'EOF'
config defaults
  option syn_flood '1'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'REJECT'

config zone
  option name 'lan'
  list network 'lan'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'

config zone
  option name 'wan'
  list network 'wan'
  list network 'wan6'
  option input 'REJECT'
  option output 'ACCEPT'
  option forward 'REJECT'
  option masq '1'
  option mtu_fix '1'

config forwarding
  option src 'lan'
  option dest 'wan'

config rule
  option name 'Allow-DHCP-Renew'
  option src 'wan'
  option proto 'udp'
  option dest_port '68'
  option target 'ACCEPT'
  option family 'ipv4'

config rule
  option name 'Allow-Ping'
  option src 'wan'
  option proto 'icmp'
  option icmp_type 'echo-request'
  option family 'ipv4'
  option target 'ACCEPT'

# ==========================================
# Docker 防火墙区域配置
# 允许 Docker 容器访问外网及局域网互访
# docker0 网桥由 Docker 服务动态创建
# ==========================================
config zone
  option name 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option network 'docker0'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

chmod +x files/etc/config/firewall
echo "✅ 防火墙基础规则配置完成（已包含 Docker 网络支持）"

# ====================================================================
# 7. 创建 Docker 防火墙启动顺序修复脚本
# 解决问题：firewall restart 会清掉 DOCKER 链，
#          dockerd restart 可能破坏转发规则或启动失败。
# 正确顺序：先 firewall restart → 再 dockerd start
# ====================================================================
echo "创建 Docker 防火墙启动修复脚本..."

mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-docker-firewall-fix << 'DOCKERFIREWALLEOF'
#!/bin/sh
# Docker 防火墙启动顺序修复脚本
# 在首次启动时执行一次，确保 firewall 规则在 dockerd 之后正确加载

# 检查是否已经执行过（避免重复执行）
if [ -f /etc/.docker_firewall_fix_done ]; then
    exit 0
fi

logger -t docker-firewall "[99-docker-firewall-fix] 开始修复 Docker 防火墙启动顺序..."

# 等待系统基本服务就绪
sleep 10

# 如果 dockerd 服务存在且正在运行，按正确顺序重启
if [ -x /etc/init.d/dockerd ]; then
    logger -t docker-firewall "[99-docker-firewall-fix] 检测到 dockerd 服务，按顺序重启..."

    # 步骤1：重启防火墙（应用 docker 区域 + 转发规则）
    /etc/init.d/firewall restart >/dev/null 2>&1
    sleep 2

    # 步骤2：启动 Docker（重建 DOCKER/DOCKER-ISOLATION 等链）
    /etc/init.d/dockerd start >/dev/null 2>&1
    sleep 3

    logger -t docker-firewall "[99-docker-firewall-fix] ✅ 防火墙和 Docker 服务已按正确顺序启动"
else
    logger -t docker-firewall "[99-docker-firewall-fix] ⚠️ dockerd 服务不存在，跳过"
fi

# 标记已完成，避免重复执行
touch /etc/.docker_firewall_fix_done

exit 0
DOCKERFIREWALLEOF

chmod +x package/base-files/files/etc/uci-defaults/99-docker-firewall-fix

# 同时创建一个 hotplug 脚本，在网络接口 up 时也触发修复
# （处理运行中重启网络/防火墙的场景）
mkdir -p package/base-files/files/etc/hotplug.d/iface
cat > package/base-files/files/etc/hotplug.d/iface/99-docker-firewall-fix << 'HOTPLUGEOF'
#!/bin/sh
# hotplug 接口事件触发：确保 Docker 网络在防火墙之后恢复
# 仅在 lan 接口 up 且 dockerd 运行时执行

[ "$ACTION" = "ifup" ] || exit 0
[ "$INTERFACE" = "lan" ] || exit 0

# 延迟等待网络稳定
sleep 5

# 检查 dockerd 是否在运行
pgrep -f dockerd > /dev/null 2>&1 || exit 0

logger -t docker-firewall "[hotplug] lan 接口 up，刷新防火墙和 Docker 网络..."
/etc/init.d/firewall restart >/dev/null 2>&1
sleep 2
/etc/init.d/dockerd start >/dev/null 2>&1
sleep 3
logger -t docker-firewall "[hotplug] ✅ 刷新完成"
HOTPLUGEOF

chmod +x package/base-files/files/etc/hotplug.d/iface/99-docker-firewall-fix
echo "✅ Docker 防火墙启动修复脚本创建完成"

# ======================================
# 8. 验证配置
# ======================================
echo "=== 验证 feeds 安装状态 ==="
ls -la package/ | grep -E "(argon|athena|helloworld)"
echo "=== 验证 feeds 源 ==="
cat feeds.conf.default | grep -E "(helloworld|istore|nas)"
echo "=== 验证无线配置 ==="
ls -la package/base-files/files/etc/uci-defaults/
echo "=== 验证防火墙配置 ==="
grep -A5 "docker" files/etc/config/firewall || echo "⚠️ Docker 防火墙配置未找到"

echo "=== 检查 OpenClash ==="
if [ -d "feeds/luci/applications/luci-app-openclash" ]; then
    echo "✅ 源码自带 OpenClash 存在"
else
    echo "⚠️ 源码自带 OpenClash 不存在，将在下次编译时恢复"
fi

echo "✅ [DIY-P2] 所有配置完成"
