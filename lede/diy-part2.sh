#!/bin/bash
# diy-part2.sh - 在 feeds install 之后执行

# ==============================================================================
# diy-part2.sh 完整成品
# 功能：CI编译阶段动态生成files，固化fstab + 95‑mmc‑docker‑prep开机脚本
# 目标设备：京东云雅典娜AX6600 IPQ60xx
# eMMC分区UUID：1a99b9cc-fa4a-4f08-a4e0-5523f260d532  mmcblk0p27 → /mnt/mmcdata
# Docker自动迁移根目录至 /mnt/mmcdata/docker
# 执行时机：feeds完成之后，make编译之前；不修改git源码，仅临时生成files
# ==============================================================================

# -------------------------- 1.动态生成files目录树 -----------------------------
rm -rf ./files
mkdir -p ./files/etc/config
mkdir -p ./files/etc/init.d
mkdir -p ./files/mnt/mmcdata

# 生成 /etc/config/fstab
cat > ./files/etc/config/fstab <<'EOF'
config global
        option anon_mount '1'
        option auto_swap '1'

config mount
        option target '/overlay'
        option device '/dev/loop0'
        option fstype 'ext4'
        option options 'rw'
        option enabled '1'
        option enabled_fsck '0'

# eMMC mmcblk0p27 内置分区
config mount
        option uuid '1a99b9cc-fa4a-4f08-a4e0-5523f260d532'
        option target '/mnt/mmcdata'
        option fstype 'ext4'
        option options 'rw,sync'
        option enabled '1'
        option enabled_fsck '1'
EOF

# 生成开机预处理脚本 95‑mmc‑docker‑prep
cat > ./files/etc/init.d/95-mmc-docker-prep <<'SCRIPT_EOF'
#!/bin/sh /etc/rc.common

START=95
STOP=0

DOCKER_ROOT="/mnt/mmcdata/docker"
MMC_DEV="/dev/mmcblk0p27"

start() {
        local cnt=0
        # 等待mmc块设备就绪，最多4秒
        while [ ! -b "${MMC_DEV}" ] && [ $cnt -lt 20 ]; do
                sleep 0.2
                cnt=$((cnt+1))
        done

        block mount

        if mountpoint -q /mnt/mmcdata; then
                mkdir -p "${DOCKER_ROOT}"
                chmod 700 "${DOCKER_ROOT}"

                uci set dockerd.settings.data_root="${DOCKER_ROOT}"
                uci set dockerd.settings.auto_start='1'
                uci commit dockerd

                # 一次性迁移旧docker数据，标记.migrated避免重复拷贝
                local old_docker="/overlay/upper/usr/share/docker"
                if [ -d "${old_docker}" ] && [ ! -f "${DOCKER_ROOT}/.migrated" ]; then
                        cp -a "${old_docker}/." "${DOCKER_ROOT}/" 2>/dev/null
                        touch "${DOCKER_ROOT}/.migrated"
                fi
        fi
}
SCRIPT_EOF

# 强制设置权限，至关重要
chmod 755 ./files/etc/init.d/95-mmc-docker-prep
chmod 755 ./files/mnt/mmcdata

# OpenWrt编译系统环境变量，注入自定义files
export FILES="$PWD/files"
echo "[diy-part2] FILES set to $FILES"

# -------------------------- 2.处理MMC内核配置，清除旧模块配置 ----------------
sed -i '/CONFIG_MMC=/d' .config
sed -i '/CONFIG_MMC_SDHCI=/d' .config
sed -i '/CONFIG_MMC_SDHCI_PLTFM=/d' .config

cat >> .config <<'CFG_EOF'
CONFIG_MMC=y
CONFIG_MMC_SDHCI=y
CONFIG_MMC_SDHCI_PLTFM=y
CFG_EOF

# -------------------------- 3.输出关键配置，CI日志方便排查 ---------------------
echo "==================== .config key options check ===================="
grep -E 'CONFIG_MMC|CONFIG_PACKAGE_block-mount|CONFIG_PACKAGE_mountpoint-utils|CONFIG_PACKAGE_dockerd' .config
echo "=================================================================="

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
