#!/bin/bash

# Cloudflare DDNS 全自动一键部署脚本
# 固定配置，自动执行，无需手动输入

set -e

# 固定配置信息
CFKEY="9283f23fbac13705d7301e32919609e4f743a"
CFUSER="wukong8667@gmail.com"
CFZONE_NAME="cfcdndns.top"
CFRECORD_NAME="hk02.cfcdndns.top"
CRON_INTERVAL="*/1 * * * *"  # 每1分钟更新

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# 显示banner
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "================================================"
    echo "     Cloudflare DDNS 全自动部署脚本"
    echo "================================================"
    echo -e "${NC}"
    echo "域名: $CFRECORD_NAME"
    echo "更新频率: 每1分钟"
    echo ""
    sleep 2
}

# 检查是否为root用户
check_root() {
    print_info "检查用户权限..."
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
    print_success "权限检查通过"
}

# 检查系统
check_system() {
    print_info "检测操作系统..."
    if [[ -f /etc/redhat-release ]]; then
        OS="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        OS="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        OS="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        OS="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        OS="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        OS="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        OS="centos"
    else
        print_error "不支持的操作系统"
        exit 1
    fi
    print_success "系统检测完成: $OS"
}

# 安装必要的工具
install_dependencies() {
    print_info "安装必要依赖..."
    if [[ "$OS" == "centos" ]]; then
        yum install -y wget curl crontabs >/dev/null 2>&1
        systemctl enable crond >/dev/null 2>&1
        systemctl start crond >/dev/null 2>&1
    else
        apt-get update >/dev/null 2>&1
        apt-get install -y wget curl cron >/dev/null 2>&1
        systemctl enable cron >/dev/null 2>&1
        systemctl start cron >/dev/null 2>&1
    fi
    print_success "依赖安装完成"
}

# 下载并配置脚本
setup_ddns_script() {
    print_info "下载DDNS脚本..."
    
    # 备份旧脚本（如果存在）
    if [[ -f /root/cf-v4-ddns.sh ]]; then
        mv /root/cf-v4-ddns.sh /root/cf-v4-ddns.sh.bak.$(date +%Y%m%d%H%M%S)
        print_warning "已备份旧脚本"
    fi
    
    # 下载脚本
    wget -N --no-check-certificate https://raw.githubusercontent.com/yulewang/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh -O /root/cf-v4-ddns.sh >/dev/null 2>&1
    
    if [[ ! -f /root/cf-v4-ddns.sh ]]; then
        print_error "脚本下载失败，尝试备用源..."
        # 如果下载失败，创建本地脚本
        create_local_ddns_script
    else
        print_success "脚本下载成功"
    fi
    
    # 配置脚本
    print_info "配置DDNS参数..."
    sed -i "s/^CFKEY=.*/CFKEY=\"$CFKEY\"/" /root/cf-v4-ddns.sh
    sed -i "s/^CFUSER=.*/CFUSER=\"$CFUSER\"/" /root/cf-v4-ddns.sh
    sed -i "s/^CFZONE_NAME=.*/CFZONE_NAME=\"$CFZONE_NAME\"/" /root/cf-v4-ddns.sh
    sed -i "s/^CFRECORD_NAME=.*/CFRECORD_NAME=\"$CFRECORD_NAME\"/" /root/cf-v4-ddns.sh
    
    # 设置执行权限
    chmod +x /root/cf-v4-ddns.sh
    print_success "配置完成"
}

# 创建本地DDNS脚本（备用）
create_local_ddns_script() {
    cat > /root/cf-v4-ddns.sh <<'EOF'
#!/bin/bash
# Cloudflare API v4 DDNS

# API key
CFKEY="9283f23fbac13705d7301e32919609e4f743a"
# Email
CFUSER="wukong8667@gmail.com"
# Zone name
CFZONE_NAME="cfcdndns.top"
# Record name
CFRECORD_NAME="hk01.cfcdndns.top"

# Get current IP
IP=$(curl -s http://ipv4.icanhazip.com)
if [ -z "$IP" ]; then
    IP=$(curl -s http://ipinfo.io/ip)
fi

# Get zone ID
CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1)

# Get record ID
CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1)

# Update record
if [ -n "$CFZONE_ID" ] && [ -n "$CFRECORD_ID" ]; then
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
      -H "X-Auth-Email: $CFUSER" \
      -H "X-Auth-Key: $CFKEY" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$IP\",\"ttl\":120,\"proxied\":false}"
    echo "$(date): Updated $CFRECORD_NAME to $IP"
else
    echo "$(date): Failed to update - Zone or Record ID not found"
fi
EOF
    chmod +x /root/cf-v4-ddns.sh
    print_success "本地脚本创建成功"
}

# 测试脚本
test_script() {
    print_info "测试DDNS更新..."
    
    # 获取当前IP
    CURRENT_IP=$(curl -s http://ipv4.icanhazip.com)
    print_info "当前服务器IP: $CURRENT_IP"
    
    # 执行脚本
    OUTPUT=$(/root/cf-v4-ddns.sh 2>&1)
    
    if echo "$OUTPUT" | grep -q -i "error\|failed"; then
        print_warning "首次执行可能失败（DNS记录可能未创建）"
        echo "$OUTPUT" | head -3
    else
        print_success "DDNS更新测试成功"
    fi
}

# 设置定时任务
setup_cron() {
    print_info "设置定时任务（每1分钟更新）..."
    
    # 删除旧的定时任务
    crontab -l 2>/dev/null | grep -v "cf-v4-ddns.sh" | crontab - 2>/dev/null || true
    
    # 添加新的定时任务
    (crontab -l 2>/dev/null; echo "$CRON_INTERVAL /root/cf-v4-ddns.sh >/dev/null 2>&1") | crontab -
    
    print_success "定时任务设置成功"
}

# 创建管理脚本
create_management_script() {
    print_info "创建管理工具..."
    
    cat > /usr/local/bin/ddns <<'EOF'
#!/bin/bash

case "$1" in
    status)
        echo "=== DDNS状态 ==="
        echo "配置域名: hk01.cfcdndns.top"
        echo "当前IP: $(curl -s http://ipv4.icanhazip.com)"
        echo "定时任务:"
        crontab -l | grep "cf-v4-ddns.sh" || echo "未设置"
        ;;
    update)
        echo "手动更新DDNS..."
        /root/cf-v4-ddns.sh
        ;;
    stop)
        crontab -l | grep -v "cf-v4-ddns.sh" | crontab -
        echo "DDNS自动更新已停止"
        ;;
    start)
        (crontab -l 2>/dev/null; echo "*/1 * * * * /root/cf-v4-ddns.sh >/dev/null 2>&1") | crontab -
        echo "DDNS自动更新已启动（每1分钟）"
        ;;
    *)
        echo "用法: ddns {status|update|stop|start}"
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/ddns
    print_success "管理工具创建成功"
}

# 最终检查
final_check() {
    print_info "执行最终检查..."
    
    # 检查脚本是否存在
    if [[ -f /root/cf-v4-ddns.sh ]]; then
        print_success "DDNS脚本已就绪"
    else
        print_error "DDNS脚本未找到"
        exit 1
    fi
    
    # 检查定时任务
    if crontab -l 2>/dev/null | grep -q "cf-v4-ddns.sh"; then
        print_success "定时任务已设置"
    else
        print_error "定时任务设置失败"
    fi
    
    # 获取IP信息
    CURRENT_IP=$(curl -s http://ipv4.icanhazip.com)
    print_success "所有检查完成"
}

# 显示完成信息
show_completion() {
    echo ""
    echo -e "${GREEN}================================================"
    echo -e "         DDNS 部署完成！"
    echo -e "================================================${NC}"
    echo ""
    echo -e "${BLUE}配置信息：${NC}"
    echo "  域名: $CFRECORD_NAME"
    echo "  更新频率: 每1分钟"
    echo "  脚本位置: /root/cf-v4-ddns.sh"
    echo ""
    echo -e "${BLUE}管理命令：${NC}"
    echo "  ddns status  - 查看状态"
    echo "  ddns update  - 手动更新"
    echo "  ddns stop    - 停止自动更新"
    echo "  ddns start   - 启动自动更新"
    echo ""
    echo -e "${YELLOW}注意事项：${NC}"
    echo "  1. 请确保Cloudflare已创建 $CFRECORD_NAME 的A记录"
    echo "  2. 请确保DNS代理状态为关闭（灰色云朵）"
    echo ""
    CURRENT_IP=$(curl -s http://ipv4.icanhazip.com)
    echo -e "${GREEN}当前IP: $CURRENT_IP${NC}"
    echo ""
}

# 主函数 - 全自动执行
main() {
    show_banner
    
    # 自动执行所有步骤
    check_root
    check_system
    install_dependencies
    setup_ddns_script
    test_script
    setup_cron
    create_management_script
    final_check
    show_completion
    
    print_success "全部完成！DDNS已开始自动更新。"
}

# 执行主函数
main
