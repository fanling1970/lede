#!/bin/bash
echo "🔧 DIY Part 1: 编译前自定义操作"
echo "执行时间: $(date)"
echo "工作目录: $(pwd)"

# ====================================================================
# 1. 验证 Docker/Dockerman feeds 源完整性
# ====================================================================
echo ""
echo "🔍 验证 dockerman 相关 feeds 包是否存在..."

DOCKER_FEEDS_OK=true

# 检查 luci-app-dockerman
if [ -d "feeds/luci/applications/luci-app-dockerman" ]; then
    echo "✅ luci-app-dockerman feeds 源存在"
else
    echo "❌ luci-app-dockerman feeds 源缺失!"
    DOCKER_FEEDS_OK=false
fi

# 检查 dockerd
if [ -d "feeds/packages/utils/dockerd" ] || [ -d "package/lean/dockerd" ]; then
    echo "✅ dockerd feeds 源存在"
else
    echo "❌ dockerd feeds 源缺失!"
    DOCKER_FEEDS_OK=false
fi

# 检查 containerd
if [ -d "feeds/packages/utils/containerd" ] || [ -d "package/lean/containerd" ]; then
    echo "✅ containerd feeds 源存在"
else
    echo "❌ containerd feeds 源缺失!"
    DOCKER_FEEDS_OK=false
fi

if [ "$DOCKER_FEEDS_OK" = false ]; then
    echo ""
    echo "⚠️  Docker 相关 feeds 不完整，尝试重新安装..."
    ./scripts/feeds update luci packages
    ./scripts/feeds install luci-app-dockerman dockerd containerd runc
fi

# ====================================================================
# 2. 列出当前可用的 Docker 相关 kmod（供排查参考）
# ====================================================================
echo ""
echo "📋 当前源码中可用的 Docker 相关内核模块:"
find package/kernel target/linux -name "Makefile" -exec grep -l -E "kmod-(cgroup|overlayfs|veth|macvlan|ipvlan|bridge|br-netfilter|ebtables|ipt-ipvs|nf-ipvs)" {} \; 2>/dev/null | \
    xargs -I{} grep -h "PKG_NAME\|TITLE" {} 2>/dev/null | \
    paste - - | sort -u | head -30 || echo "(未找到匹配的内核模块定义)"

# ====================================================================
# 3. 通用补丁（按需启用）
# ====================================================================
# if [ -d "../patches" ]; then
#     for patch_file in ../patches/*.patch; do
#         if [ -f "$patch_file" ]; then
#             echo "🩹 应用补丁: $(basename $patch_file)"
#             patch -p1 < "$patch_file" || echo "⚠️ 补丁应用失败: $(basename $patch_file)"
#         fi
#     done
# fi

# ====================================================================
# 4. 添加自定义软件包（按需启用）
# ====================================================================
# if [ -d "../custom-packages" ]; then
#     cp -r ../custom-packages/* package/custom/
#     echo "✅ 已复制自定义软件包"
# fi

echo ""
echo "✅ DIY Part 1 完成"
