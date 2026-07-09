# 提前删除官方openclash，避免优先级冲突
rm -rf feeds/luci/applications/luci-app-openclash
# 提前删除官方passwall，避免优先级冲突
rm -rf feeds/luci/applications/luci-app-passwall

# 清理重复源
sed -i '/src-git kenzo/d' feeds.conf.default
sed -i '/src-git small/d' feeds.conf.default
sed -i '/src-git istore/d' feeds.conf.default
sed -i '/src-git nas /d' feeds.conf.default
sed -i '/src-git nas_luci/d' feeds.conf.default

# 写入软件源
sed -i '$a src-git kenzo https://github.com/kenzok8/openwrt-packages' feeds.conf.default
sed -i '$a src-git small https://github.com/kenzok8/small' feeds.conf.default
sed -i '$a \\nsrc-git istore https://github.com/linkease/istore;main' feeds.conf.default
sed -i '$a \\nsrc-git nas https://github.com/linkease/nas-packages.git;master' feeds.conf.default
sed -i '$a src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' feeds.conf.default

cat feeds.conf.default

# 删除残缺的旧small目录，强制重新克隆完整仓库
rm -rf feeds/small
./scripts/feeds update -a
./scripts/feeds install -a
