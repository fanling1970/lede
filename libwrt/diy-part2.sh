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
sed -i "s/hostname='.*'/hostname='LibWrt'/g" package/base-files/files/bin/config_generate

# 修改版本描述
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g" package/lean/default-settings/files/zzz-default-settings   
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By J.Y'/g" package/lean/default-settings/files/zzz-default-settings

# 修改默认网关 IP
sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

# 清除默认密码
sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings

# 添加 iStore 频道信息（优化：防止上游更新导致行号错位）
if ! grep -q "istore.channel" package/lean/default-settings/files/zzz-default-settings; then
    sed -i "/^uci commit istore/i uci set istore.istore.channel='OpenWrt'" \
        package/lean/default-settings/files/zzz-default-settings
fi

echo "✅ 基础系统设置修改完成"

# ======================================
# 3. 清理冲突包（保留源码自带 OpenClash）
# ======================================
echo "--- 清理冲突包 ---"

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

# ======================================
# 6. 防火墙配置与 Docker 兼容性修复
# ======================================
echo "--- 配置防火墙与 Docker 修复 ---"

# 【重要】不覆盖 files/etc/config/firewall，保留源码默认完整配置
# 改为使用 uci-defaults 在首次启动时增量修改
mkdir -p package/base-files/files/etc/uci-defaults

cat > package/base-files/files/etc/uci-defaults/98-docker-firewall-fix << 'FWEOF'
#!/bin/sh
# === Docker 防火墙兼容性修复（首次启动执行） ===

# 1. 确保 docker -> wan 转发规则存在
if [ -z "$(uci -q get firewall.@forwarding[-1].src | grep docker)" ]; then
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='docker'
    uci set firewall.@forwarding[-1].dest='wan'
    uci commit firewall
fi

# 2. 保护 Docker NAT 链不被 fw3 清除
cat >> /etc/firewall.user << 'USEREOF'

# Docker NAT chain protection
iptables -t nat -N DOCKER 2>/dev/null || true
iptables -t nat -N DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
iptables -t nat -N DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
iptables -t filter -N DOCKER 2>/dev/null || true
iptables -t filter -N DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
iptables -t filter -N DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
USEREOF

exit 0
FWEOF
chmod +x package/base-files/files/etc/uci-defaults/98-docker-firewall-fix

# 3. 注入 rc.local Docker FORWARD 补全脚本
mkdir -p files/etc
cat > files/etc/rc.local << 'RCEOF'
#!/bin/sh

# Docker FORWARD 规则补全（配合 firewall reload 使用）
(
    for i in $(seq 1 30); do
        if ip link show docker0 &>/dev/null; then
            sleep 3
            /etc/init.d/firewall reload
            if ! iptables -C FORWARD -i docker0 -o !docker0 -j ACCEPT 2>/dev/null; then
                iptables -I FORWARD -i docker0 -o !docker0 -j ACCEPT
            fi
            if ! iptables -C FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
                iptables -I FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            fi
            logger -t docker-fix "Firewall reloaded & FORWARD rules patched"
            break
        fi
        sleep 1
    done
) &

exit 0
RCEOF
chmod +x files/etc/rc.local

echo "✅ 防火墙与 Docker 修复配置完成"

# ======================================
# 7. 验证配置
# ======================================
echo "=== 验证 feeds 安装状态 ==="
ls -la package/ | grep -E "(argon|athena|helloworld)"
echo "=== 验证 feeds 源 ==="
cat feeds.conf.default | grep -E "(helloworld|istore|nas)"
echo "=== 验证无线与Docker修复配置 ==="
ls -la package/base-files/files/etc/uci-defaults/

echo "=== 检查 OpenClash ==="
if [ -d "feeds/luci/applications/luci-app-openclash" ]; then
    echo "✅ 源码自带 OpenClash 存在"
else
    echo "⚠️ 源码自带 OpenClash 不存在，将在下次编译时恢复"
fi

echo "✅ [DIY-P2] 所有配置完成"
