#!/bin/bash

set -e

# === 你需要填写的 Cloudflare 配置信息 ===
CFKEY="9283f23fbac13705d7301e32919609e4f743a"
CFUSER="wukong8667@gmail.com"
CFZONE_NAME="cfcdndns.top"
CFRECORD_NAME="hk02.cfcdndns.top"
# =======================================

DDNS_SH="/root/cf-v4-ddns.sh"
CFG="/root/cf-ddns.conf"
LOGF="/var/log/cf-ddns-setup.log"
CRON_MARK="$DDNS_SH"
export HOME="/root"   # 防止因HOME未定义而报错

exec > >(tee -a "$LOGF") 2>&1

echo -e "\033[1;32m------ Cloudflare DDNS 自动安装启动 ------\033[0m"
echo "[0/7] 准备中..."

# 0. 判断/保存配置
save_conf() {
    cat <<EOF >"$CFG"
CFKEY="$CFKEY"
CFUSER="$CFUSER"
CFZONE_NAME="$CFZONE_NAME"
CFRECORD_NAME="$CFRECORD_NAME"
EOF
}
save_conf

# 1. 检查依赖
echo -e "\033[1;32m[1/7] 检查并安装依赖...\033[0m"
MISSING=""
for p in curl wget sed; do command -v $p >/dev/null 2>&1 || MISSING="$MISSING $p"; done

if ! command -v crond >/dev/null 2>&1 && ! command -v cron >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        MISSING="$MISSING cron"
    elif command -v yum >/dev/null 2>&1; then
        MISSING="$MISSING cronie"
    fi
fi

if [ -n "$MISSING" ]; then
    echo "需安装依赖: $MISSING"
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y $MISSING
    elif command -v yum >/dev/null 2>&1; then
        yum -y install $MISSING
    else
        echo "[FATAL] 不支持的 Linux 分支，无包管理器"
        exit 1
    fi
fi

# 启动定时任务服务
if command -v crond >/dev/null 2>&1; then
    systemctl enable crond 2>/dev/null || true
    systemctl start crond 2>/dev/null || service crond start 2>/dev/null || /etc/init.d/crond start 2>/dev/null || true
elif command -v cron >/dev/null 2>&1; then
    systemctl enable cron 2>/dev/null || true
    systemctl start cron 2>/dev/null || service cron start 2>/dev/null || /etc/init.d/cron start 2>/dev/null || true
fi

echo "依赖可用，计划任务OK"

# 2. 获取公网 IP
echo -e "\033[1;32m[2/7] 检查并等待公网IP就绪...\033[0m"
PUBIP=""
MAXWAIT=150
INTERVAL=5
timeout=0
getip4() {
    for u in \
        "http://169.254.169.254/latest/meta-data/public-ipv4" \
        "https://api-ipv4.ip.sb/ip" \
        "https://ipv4.icanhazip.com" \
        "http://api.ipify.org" \
        "http://ifconfig.me"
    do
        ip=$(curl -s --max-time 6 "$u" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        if [ -n "$ip" ]; then echo "$ip"; return 0; fi
    done
    return 1
}
while [ "$timeout" -le "$MAXWAIT" ]; do
    PUBIP=$(getip4)
    [ -n "$PUBIP" ] && break
    sleep $INTERVAL
    ((timeout += INTERVAL))
done
if [ -z "$PUBIP" ]; then
    echo "[FATAL] 150秒内未获取到公网出口IP！请先在云平台分配弹性公网IP或等待网络就绪再试。"
    exit 1
fi
echo "已获取公网IP: $PUBIP"

# 3. 下载并配置Cloudflare DDNS 主脚本
echo -e "\033[1;32m[3/7] 正在下载安装 Cloudflare DDNS 脚本...\033[0m"
if [ -f "$DDNS_SH" ]; then
    mv "$DDNS_SH" "$DDNS_SH.bak.$(date +%s)"
fi
wget -q -N --no-check-certificate https://raw.githubusercontent.com/yulewang/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh -O "$DDNS_SH"
chmod +x "$DDNS_SH"

# 4. 注入参数（保证脚本变量对齐）
echo -e "\033[1;32m[4/7] 写入Cloudflare参数...\033[0m"
sed -i "s/^CFKEY=.*/CFKEY=\"$CFKEY\"/" "$DDNS_SH"
sed -i "s/^CFUSER=.*/CFUSER=\"$CFUSER\"/" "$DDNS_SH"
sed -i "s/^CFZONE_NAME=.*/CFZONE_NAME=\"$CFZONE_NAME\"/" "$DDNS_SH"
sed -i "s/^CFRECORD_NAME=.*/CFRECORD_NAME=\"$CFRECORD_NAME\"/" "$DDNS_SH"

# 5. 首次同步（修正HOME防止“unbound variable”错误）
echo -e "\033[1;32m[5/7] 首次同步DDNS...\033[0m"
export HOME="/root"
bash "$DDNS_SH" || {
    echo -e "\033[1;31m[FATAL] 首次执行Cloudflare DDNS脚本失败，请检查CF密钥/域名是否正确及本机是否已绑定DNS记录。\033[0m"
    exit 1
}

# 6. 写crontab（加HOME，防止crontab环境问题）
echo -e "\033[1;32m[6/7] 加入crontab定时任务...\033[0m"
(crontab -l 2>/dev/null | grep -v "$CRON_MARK"; echo "*/1 * * * * HOME=/root $DDNS_SH >/dev/null 2>&1") | crontab -

# 7. 增加计划自愈一行，防止crontab丢失
(crontab -l 2>/dev/null | grep -v "$0"; echo "*/5 * * * * grep -q '$CRON_MARK' <(crontab -l) || (crontab -l | grep -v '$CRON_MARK'; echo '*/1 * * * * HOME=/root $DDNS_SH >/dev/null 2>&1') | crontab -") | crontab -

echo -e "\033[1;32m[7/7] 完成！\nCloudflare DDNS已启用，今后每分钟自动同步公网IP。\033[0m"
echo "如需维护/更新/卸载，再次运行本脚本即可，日志见 $LOGF"
exit 0
