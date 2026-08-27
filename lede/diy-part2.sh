#!/bin/bash
# diy-part2.sh - 在 feeds install 之后执行

# ============================================================
# Docker 存储迁移至 eMMC (mmcblk0p27) 自动化配置
# 适用于: 京东云雅典娜 / LEDE / GitHub Actions 云编译
# ============================================================

# 在 diy-part2.sh 开头加一行调试，Actions 日志中可查看实际路径
find . -path "*/dockerd" -name "dockerd" 2>/dev/null | head -5

echo ">>> [DIY-PART2] 配置 Docker 数据根目录至 mmcblk0p27..."

# 1. 修改 Dockerman UCI 默认配置
# 注意: 必须在 package/lean/luci-app-dockerman 或相关 dockerd 包编译前/后处理
# 这里通过修改默认配置文件实现，确保首次启动即为新路径
DOCKERD_DEFAULTS="package/lean/luci-app-dockerman/root/etc/config/dockerd"
if [ -f "$DOCKERD_DEFAULTS" ]; then
    sed -i "s|option data_root.*|option data_root '/mnt/mmcblk0p27/docker'|" "$DOCKERD_DEFAULTS"
    # 如果原文件没有 wait_path，则追加；如果有则替换
    if grep -q "option wait_path" "$DOCKERD_DEFAULTS"; then
        sed -i "s|option wait_path.*|option wait_path '/mnt/mmcblk0p27/docker'|" "$DOCKERD_DEFAULTS"
    else
        sed -i "/option data_root/a\\toption wait_path '/mnt/mmcblk0p27/docker'" "$DOCKERD_DEFAULTS"
    fi
    echo "    ✔ dockerd UCI defaults 已修改"
else
    echo "    ⚠ 未找到 $DOCKERD_DEFAULTS，请检查 dockerman 包路径是否变更"
fi

# 2. 注入 fstab 挂载配置 (uci-defaults 方式，仅首次启动执行)
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-docker-emmc-mount << 'UCIEOF'
#!/bin/sh
# === 首次启动: 配置 mmcblk0p27 为 Docker 存储分区 ===

# 替代方案: 如果条目不存在则新建
if ! uci -q get fstab.@mount[-1].device | grep -q "mmcblk0p27"; then
    uci add fstab mount
    uci set fstab.@mount[-1].device='/dev/mmcblk0p27'
    uci set fstab.@mount[-1].target='/mnt/mmcblk0p27'
    uci set fstab.@mount[-1].fstype='ext4'
fi
uci set fstab.@mount[-1].enabled='1'
uci set fstab.@mount[-1].options='rw,noatime,nodiratime,discard'
uci commit fstab

# 写入 rc.local 可靠挂载脚本 (在 exit 0 之前插入)
RC_LOCAL="/etc/rc.local"
if ! grep -q "docker-mount" "$RC_LOCAL" 2>/dev/null; then
    sed -i '/^exit 0$/i\
# === Docker eMMC 可靠挂载 ===\
(\
    COUNT=0\
    while [ ! -b /dev/mmcblk0p27 ] && [ $COUNT -lt 30 ]; do\
        sleep 0.5\
        COUNT=$((COUNT+1))\
    done\
    if [ -b /dev/mmcblk0p27 ]; then\
        mkdir -p /mnt/mmcblk0p27\
        if ! mountpoint -q /mnt/mmcblk0p27; then\
            mount -o rw,noatime,nodiratime,discard /dev/mmcblk0p27 /mnt/mmcblk0p27\
            logger -t docker-mount "mmcblk0p27 mounted successfully"\
        fi\
    else\
        logger -t docker-mount "ERROR: mmcblk0p27 not found after timeout!"\
    fi\
) &\
' "$RC_LOCAL"
fi

# 标记已执行，防止重复运行
touch /tmp/.docker_emmc_configured
UCIEOF

chmod +x files/etc/uci-defaults/99-docker-emmc-mount
echo "    ✔ uci-defaults 挂载脚本已注入"

echo ">>> [DIY-PART2] Docker eMMC 配置完成"


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
# 6. 验证配置
# ======================================
echo "=== 验证 feeds 安装状态 ==="
ls -la package/ | grep -E "(argon|athena|helloworld)"
echo "=== 验证 feeds 源 ==="
cat feeds.conf.default | grep -E "(helloworld|istore|nas)"
echo "=== 检查 OpenClash ==="
if [ -d "feeds/luci/applications/luci-app-openclash" ]; then
    echo "✅ 源码自带 OpenClash 存在"
else
    echo "⚠️ 源码自带 OpenClash 不存在，将在下次编译时恢复"
fi


echo "✅ [DIY-P2] 所有配置完成"
