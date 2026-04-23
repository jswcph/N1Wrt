#!/bin/bash
source shell/custom-packages.sh
# 该文件实际为imagebuilder容器内的build.sh

if [ -n "$CUSTOM_PACKAGES" ]; then
  echo "✅ 你选择了第三方软件包：$CUSTOM_PACKAGES"
  if [ "$PROFILE" = "glinet_gl-mt3000" ]; then
    echo "❌ 检查到您集成了第三方软件包 由于mt3000闪存空间较小 不支持此操作"
    echo "✅ 系统将自动帮你注释掉shell/custom-packages.sh中的插件 目前支持第三方插件集成的机型是mt2500/mt6000等大闪存机型"
    CUSTOM_PACKAGES=""
  else
    # 下载 run 文件仓库
    echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

    # 拷贝 run/arm64 下所有 run 文件和ipk文件 到 extra-packages 目录
    mkdir -p /home/build/immortalwrt/extra-packages
    cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

    echo "✅ Run files copied to extra-packages:"
    ls -lh /home/build/immortalwrt/extra-packages/*.run
    # 解压并拷贝ipk到packages目录
    sh shell/prepare-packages.sh
    ls -lah /home/build/immortalwrt/packages/
    # 添加架构优先级信息
    sed -i '1i\
    arch aarch64_generic 10\n\
    arch aarch64_cortex-a53 15' repositories.conf
  fi
else
  echo "⚪️ 未选择任何第三方软件包"
fi
# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
echo "Include Docker: $INCLUDE_DOCKER"
echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入pppoe变量————>pppoe-settings文件
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting build process..."


# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES kmod-zram"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-filebrowser-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
#PACKAGES="$PACKAGES luci-app-argon-config"
#PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
#23.05
PACKAGES="$PACKAGES luci-i18n-opkg-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"
#PACKAGES="$PACKAGES luci-app-openclash"
#PACKAGES="$PACKAGES luci-i18n-homeproxy-zh-cn"
#PACKAGES="$PACKAGES openssh-sftp-server"
# 增加几个必备组件 方便用户安装iStore
PACKAGES="$PACKAGES fdisk"
PACKAGES="$PACKAGES script-utils"
#PACKAGES="$PACKAGES luci-i18n-samba4-zh-cn"
# 第三方软件包 合并
# ======== shell/custom-packages.sh =======
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi
# 修改默认主机名
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/system
config system
    option hostname 'OpenWrt'
    option zonename 'Asia/Shanghai'
    option timezone 'CST-8'

config timeserver 'ntp'
    list server 'ntp.aliyun.com'
    list server 'time1.cloud.tencent.com'
    option enabled '1'
    option enable_server '0'
EOF
# 创建 WiFi 自动配置脚本
mkdir -p /home/build/immortalwrt/files/etc/uci-defaults
cat << 'EOF' > /home/build/immortalwrt/files/etc/uci-defaults/98-wireless-setup
#!/bin/sh

# 配置 radio0 (通常对应 2.4G)
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.htmode='HT40'
uci set wireless.default_radio0.ssid='OpenWrt_2.4G'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='password'

# 配置 radio1 (通常对应 5G)
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.htmode='HE160'
uci set wireless.default_radio1.ssid='OpenWrt_5G'
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.default_radio1.key='password'

# 提交配置并应用
uci commit wireless
wifi up
exit 0
EOF
sed -i "s|^root:[^:]*:|root:\$1\$v9pS879.\$6Mc.B56mN0pM.1mS91pM.1:|g" /etc/shadow

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
