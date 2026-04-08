#!/bin/bash
source shell/custom-packages.sh
# 该文件实际为imagebuilder容器内的build.sh

# 下载 run 文件仓库
echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

# 【关键修改】NN6000 虽然是 IPQ6000，但依然属于 arm64/aarch64 架构，复用 arm64 目录
mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

echo "✅ Run files copied to extra-packages:"
ls -lh /home/build/immortalwrt/extra-packages/*.run

# 解压并拷贝ipk到packages目录
sh shell/prepare-packages.sh
ls -lah /home/build/immortalwrt/packages/

# 【关键修改】针对 IPQ60xx 平台的架构优先级
sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf

# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
echo "Include Docker: $INCLUDE_DOCKER"

# 创建配置目录
mkdir -p /home/build/immortalwrt/files/etc/config
mkdir -p /home/build/immortalwrt/files/etc/uci-defaults

# 创建pppoe配置文件
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# 【新增】针对 NN6000 的 WiFi 顺序特殊处理脚本 (radio0=5G, radio1=2.4G)
cat << 'EOF' > /home/build/immortalwrt/files/etc/uci-defaults/98-wireless-setup
#!/bin/sh
# NN6000 特殊映射：radio0 为 5G，radio1 为 2.4G
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.htmode='HE80' # IPQ6000 通常稳定在 80MHz
uci set wireless.default_radio0.ssid='NN6000_5G'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='password'

uci set wireless.radio1.disabled='0'
uci set wireless.radio1.htmode='HT40'
uci set wireless.default_radio1.ssid='NN6000_2.4G'
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.default_radio1.key='password'

uci commit wireless
wifi up
exit 0
EOF

# 【核心修改】强制注入 password 密文，确保不为空密码
cat << 'EOF' > /home/build/immortalwrt/files/etc/uci-defaults/99-set-password
#!/bin/sh
sed -i 's/^root:[^:]*:/root:$1$wBy6recl$99v76S0hio48995E.pX9V.:/' /etc/shadow
exit 0
EOF
chmod +x /home/build/immortalwrt/files/etc/uci-defaults/*

# 定义软件包列表 (保持 AX3000T 的精简配置)
PACKAGES=""
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn"
PACKAGES="$PACKAGES zram-config kmod-zram" # NN6000 内存虽大，开启 zram 依然能提高稳定性
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-app-wol luci-i18n-wol-zh-cn" # 网络唤醒
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server luci-i18n-filemanager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-dufs-zh-cn" # 静态文件服务器

# NN6000 有 USB3.0，添加 USB 支持
PACKAGES="$PACKAGES kmod-usb3 kmod-usb-storage kmod-fs-ntfs3 kmod-fs-ext4"

# 插件选择逻辑
if [ "$PROFILE" = "glinet_gl-axt1800" ]; then
    PACKAGES="$PACKAGES -luci-i18n-diskman-zh-cn luci-i18n-homeproxy-zh-cn"
else
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

# Docker 支持 (NN6000 512MB RAM 非常适合跑 Docker)
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# 构建镜像
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files"

if [ $? -ne 0 ]; then
    exit 1
fi
