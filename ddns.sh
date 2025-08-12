#!/bin/bash

# =================== 配置区(首装可不改, 菜单第3项可手动填写) ===================
CFKEY="9283f23fbac13705d7301e32919609e4f743a"            # Cloudflare Global API Key
CFUSER="wukong8667@gmail.com"           # Cloudflare账户Email
CFZONE_NAME="cfcdndns.top"      # 主域名(如：example.com)
CFRECORD_NAME="hk02.cfcdndns.top"    # 解析子域名(如：ddns.example.com)
# ===========================================================================

CFG="/root/cf-ddns.conf"
DDNS_SH="/root/cf-v4-ddns.sh"
CRON_MARK="$DDNS_SH"
LOGF="/var/log/cf-ddns-manager.log"

log_green()  { echo -e "\033[1;32m$1\033[0m"; }
log_red()    { echo -e "\033[1;31m$1\033[0m"; }
log_blue()   { echo -e "\033[1;36m$1\033[0m"; }

load_conf() {
    # 优先读配置文件
    if [ -f "$CFG" ]; then
        source "$CFG"
    fi
}

save_conf() {
    cat <<EOF >$CFG
CFKEY="$CFKEY"
CFUSER="$CFUSER"
CFZONE_NAME="$CFZONE_NAME"
CFRECORD_NAME="$CFRECORD_NAME"
EOF
}

apply_config_ddns_sh() {
    sed -i "s/^CFKEY=.*/CFKEY=\"$CFKEY\"/" "$DDNS_SH"
    sed -i "s/^CFUSER=.*/CFUSER=\"$CFUSER\"/" "$DDNS_SH"
    sed -i "s/^CFZONE_NAME=.*/CFZONE_NAME=\"$CFZONE_NAME\"/" "$DDNS_SH"
    sed -i "s/^CFRECORD_NAME=.*/CFRECORD_NAME=\"$CFRECORD_NAME\"/" "$DDNS_SH"
}

change_config() {
    log_blue "请输入Cloudflare 配置信息:"
    read -rp "全局API KEY                 : " CFKEY
    read -rp "Email(账户邮箱)               : " CFUSER
    read -rp "主域名(example.com)           : " CFZONE_NAME
    read -rp "记录名(完整如ddns.example.com): " CFRECORD_NAME
    save_conf
    if [ -f "$DDNS_SH" ]; then apply_config_ddns_sh; fi
    log_green "配置已保存"
}

uninstall() {
    log_blue "正在卸载Cloudflare DDNS..."
    crontab -l 2>/dev/null | grep -v "$CRON_MARK" | crontab -
    [ -f "$DDNS_SH" ] && rm -f "$DDNS_SH"
    [ -f "$CFG" ] && rm -f "$CFG"
    log_green "卸载完成，crontab及脚本、配置已清理！"
}

restart_ddns() {
    load_conf
    if [ ! -f "$DDNS_SH" ]; then log_red "未安装DDNS脚本"; exit 1; fi
    bash "$DDNS_SH"
}

show_menu() {
    log_green "========= Cloudflare DDNS 管理菜单 ========="
    echo "1. 卸载"
    echo "2. 执行一次DDNS同步（立即）"
    echo "3. 更改 Cloudflare 配置"
    echo "4. 退出"
    echo "--------------------------------------"
    read -rp "请选择操作[1-4]: " act
    case "$act" in
        1) uninstall ;;
        2) restart_ddns ;;
        3) change_config ; [ -f "$DDNS_SH" ] && apply_config_ddns_sh && log_green "DDNS主脚本配置已同步" ;;
        4) exit 0 ;;
        *) log_red "无效选项"; exit 1 ;;
    esac
    exit 0
}

# 进入管理菜单：如已安装过且有参数/配置，就弹出菜单退出
if [ -f "$DDNS_SH" ] && { [ -f "$CFG" ] || [ -n "$CFKEY" ]; } && [ -z "$1" ]; then
    load_conf
    show_menu
fi

# ========== 【以下为首次自动装机流程】 ==========

exec > >(tee -a $LOGF) 2>&1

# root检查
if [ "$EUID" -ne 0 ]; then log_red "请用root账号运行本脚本"; exit 1; fi

# 读取参数
load_conf

if [ -z "$CFKEY" ] || [ -z "$CFUSER" ] || [ -z "$CFZONE_NAME" ] || [ -z "$CFRECORD_NAME" ]; then
    log_red "未填写Cloudflare参数，可菜单选择【3】更改配置后再安装！"
    change_config
fi

save_conf

log_green "\n【1/7】检测基础依赖中..."
MISSING=""
for p in curl wget sed; do command -v $p >/dev/null 2>&1 || MISSING="$MISSING $p"; done

CRONSVC=""
if command -v crond >/dev/null 2>&1; then
    CRONSVC=crond
elif command -v cron >/dev/null 2>&1; then
    CRONSVC=cron
elif command -v apt >/dev/null 2>&1; then
    MISSING="$MISSING cron"
elif command -v yum >/dev/null 2>&1; then
    MISSING="$MISSING cronie"
fi

if [ -n "$MISSING" ]; then
    log_blue "需要安装依赖:$MISSING"
    if command -v apt >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y $MISSING
    elif command -v yum >/dev/null 2>&1; then
        yum install -y $MISSING
    else
        log_red "未知系统，请手动安装:$MISSING"
        exit 1
    fi
fi

# 启动cron服务
if command -v crond >/dev/null 2>&1; then
    systemctl enable crond; systemctl start crond
elif command -v cron >/dev/null 2>&1; then
    systemctl enable cron; systemctl start cron
else
    log_red "计划任务服务(crond/cron)不可用，请手动安装/启动！"
    exit 1
fi

log_green "依赖与计划任务服务 检查通过"

log_green "\n【2/7】检测公网IP..."
# AWS元数据优先，（169.254.169.254），否则多接口获取
getip4() {
    for u in \
        "http://169.254.169.254/latest/meta-data/public-ipv4" \
        "https://api-ipv4.ip.sb/ip" \
        "https://ipv4.icanhazip.com" \
        "http://api.ipify.org" \
        "http://ifconfig.me"
    do
        ip=$(curl -s --max-time 6 "$u" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        [ -n "$ip" ] && echo "$ip" && return 0
    done
    return 1
}
MAXWAIT=150
INTERVAL=5
timeout=0
PUBIP=""
while [ "$timeout" -le "$MAXWAIT" ]; do
    PUBIP=$(getip4)
    [ -n "$PUBIP" ] && break
    sleep $INTERVAL
    ((timeout += INTERVAL))
done

if [ -z "$PUBIP" ]; then
    log_red "150秒内未获取到公网IP，请确保VPS出口畅通，有公网IP"
    exit 1
fi
log_green "检测到公网出口IP: $PUBIP"

log_green "\n【3/7】下载并装配Cloudflare DDNS主脚本"

if [ -f "$DDNS_SH" ]; then
    mv "$DDNS_SH" "$DDNS_SH.bak.$(date +%s)"
fi
wget -q -N --no-check-certificate https://raw.githubusercontent.com/yulewang/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh -O "$DDNS_SH" || { log_red "脚本下载失败"; exit 1; }
[ -f "$DDNS_SH" ] || { log_red "脚本未能落盘"; exit 1; }
chmod +x "$DDNS_SH"
apply_config_ddns_sh

log_green "\n【4/7】首次同步DDNS..."
bash "$DDNS_SH" || {
    log_red "首次执行Cloudflare DDNS脚本失败，请检查CF密钥/域名是否正确及本机是否已绑定DNS记录。"
    exit 1
}

log_green "\n【5/7】添加crontab定时同步任务..."
crontab -l 2>/dev/null | grep -v "$CRON_MARK" | (cat; echo "*/1 * * * * $DDNS_SH >/dev/null 2>&1") | crontab -

log_green "\n【6/7】添加定时自愈任务(守护DDNS计划存在)..."
(crontab -l 2>/dev/null | grep -v "$0"; echo "*/5 * * * * grep -q '$CRON_MARK' <(crontab -l) || (crontab -l | grep -v '$CRON_MARK'; echo '*/1 * * * * $DDNS_SH >/dev/null 2>&1') | crontab -") | crontab -

log_green "\n【7/7】安装完毕！"
echo -e "Cloudflare DDNS自动装机完毕，公网IP已同步。\n如需维护请再次运行本脚本进入菜单。\n日志：$LOGF"
log_green "============================================="
exit 0
