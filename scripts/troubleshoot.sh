#!/bin/bash
# 电影推荐系统问题诊断与修复脚本
# 作者：电影推荐系统团队
# 日期：2025-05-10

set -e

# 日志颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2
}

check_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

check_fail() {
    echo -e "${RED}[✗] $1${NC}"
}

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
CONFIG_FILE="$INSTALL_DIR/config/database.conf"
SERVICE_FILE="/etc/systemd/system/movie-recommender.service"

# 获取当前脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

# 显示诊断头部
echo "============================================================"
echo "      电影推荐系统诊断与修复工具 - v1.0"
echo "============================================================"
echo "运行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "主机名: $(hostname)"
echo "IP地址: $(hostname -I | awk '{print $1}')"
echo "============================================================"

# 参数解析
FIX_ISSUES=0
INTERACTIVE=1

while getopts "fy" opt; do
  case ${opt} in
    f )
      FIX_ISSUES=1
      ;;
    y )
      INTERACTIVE=0
      FIX_ISSUES=1
      ;;
    \? )
      echo "用法: $0 [-f] [-y]"
      echo "  -f: 自动修复发现的问题"
      echo "  -y: 非交互模式，自动确认所有修复操作"
      exit 1
      ;;
  esac
done

# 询问是否执行修复
ask_fix() {
    if [ $FIX_ISSUES -eq 0 ]; then
        return 1
    fi
    
    if [ $INTERACTIVE -eq 1 ]; then
        read -p "是否修复此问题? [y/N] " answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            return 1
        fi
    fi
    return 0
}

# 1. 检查安装目录
echo "正在检查安装目录..."
if [ -d "$INSTALL_DIR" ]; then
    check_success "安装目录存在: $INSTALL_DIR"
else
    check_fail "安装目录不存在: $INSTALL_DIR"
    if ask_fix; then
        log_info "创建安装目录..."
        mkdir -p "$INSTALL_DIR"
        log_info "请重新部署系统: sudo bash scripts/deploy.sh"
        exit 1
    fi
fi

# 2. 检查配置文件
echo "正在检查配置文件..."
if [ -f "$CONFIG_FILE" ]; then
    check_success "配置文件存在: $CONFIG_FILE"
    
    # 检查端口配置
    SERVICE_PORT=$(grep "^port" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    if [ -n "$SERVICE_PORT" ]; then
        check_success "服务端口配置: $SERVICE_PORT"
    else
        check_fail "无法从配置文件读取端口信息"
        if ask_fix; then
            log_info "添加默认端口配置..."
            sed -i 's/\[service\]/\[service\]\nport = 80/' "$CONFIG_FILE"
            SERVICE_PORT=80
        fi
    fi
else
    check_fail "配置文件不存在: $CONFIG_FILE"
    if ask_fix; then
        log_info "创建默认配置文件..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" << EOF
[database]
host = localhost
port = 3306
user = douban_user
password = MySQL_20050816Zln@233
db = douban
charset = utf8mb4
pool_size = 5
timeout = 60
reconnect_attempts = 3

[service]
port = 80
token = HelloMovieRecommender
encoding_key = X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a
debug = false
log_level = INFO

[recommender]
similarity_threshold = 0.5
min_ratings = 3
max_recommendations = 10
EOF
        log_info "已创建默认配置文件"
        SERVICE_PORT=80
    fi
fi

# 3. 检查系统服务
echo "正在检查系统服务..."
if [ -f "$SERVICE_FILE" ]; then
    check_success "服务文件存在: $SERVICE_FILE"
    
    # 检查特权端口绑定权限
    if grep -q "CAP_NET_BIND_SERVICE" "$SERVICE_FILE"; then
        check_success "服务配置中已包含特权端口绑定权限"
    else
        check_fail "服务配置中缺少特权端口绑定权限"
        if ask_fix; then
            log_info "添加特权端口绑定权限..."
            sed -i '/\[Service\]/a AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE' "$SERVICE_FILE"
            log_info "已添加特权端口绑定权限，需要重载服务配置"
            systemctl daemon-reload
        fi
    fi
    
    # 检查服务启动状态
    if systemctl is-active --quiet movie-recommender.service; then
        check_success "服务已启动并正在运行"
    else
        check_fail "服务未运行"
        if ask_fix; then
            log_info "尝试启动服务..."
            systemctl start movie-recommender.service
            sleep 3
            if systemctl is-active --quiet movie-recommender.service; then
                check_success "服务已成功启动"
            else
                log_error "服务启动失败，请检查日志:"
                journalctl -u movie-recommender.service -n 30
            fi
        fi
    fi
else
    check_fail "服务文件不存在: $SERVICE_FILE"
    if ask_fix; then
        log_info "创建服务文件..."
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender
# 允许绑定特权端口(80)
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
        log_info "服务文件已创建，重载服务配置..."
        systemctl daemon-reload
        log_info "启用并启动服务..."
        systemctl enable movie-recommender.service
        systemctl start movie-recommender.service
    fi
fi

# 4. 检查端口占用
echo "正在检查端口占用情况..."
if [ -n "$SERVICE_PORT" ]; then
    PORT_PID=$(netstat -tuln | grep ":$SERVICE_PORT " | awk '{print $7}' | cut -d'/' -f1)
    if [ -n "$PORT_PID" ]; then
        PORT_PROC=$(ps -p $PORT_PID -o comm=)
        if [[ "$PORT_PROC" == *"python"* ]]; then
            check_success "端口 $SERVICE_PORT 被Python进程占用，可能是本系统"
        else
            check_fail "端口 $SERVICE_PORT 被其他进程占用: $PORT_PROC (PID: $PORT_PID)"
            if ask_fix; then
                if [ $SERVICE_PORT -eq 80 ]; then
                    log_info "检测到80端口冲突，配置Nginx反向代理..."
                    if [ -f "$INSTALL_DIR/scripts/setup_nginx.sh" ]; then
                        bash "$INSTALL_DIR/scripts/setup_nginx.sh"
                    else
                        log_error "未找到Nginx配置脚本，请手动配置反向代理"
                    fi
                else
                    log_warning "请手动解决端口冲突或更改配置端口"
                fi
            fi
        fi
    else
        check_fail "端口 $SERVICE_PORT 未被占用，可能服务未正常启动"
        if ask_fix; then
            log_info "尝试重启服务..."
            systemctl restart movie-recommender.service
            sleep 3
            if netstat -tuln | grep -q ":$SERVICE_PORT "; then
                check_success "服务已成功绑定到端口 $SERVICE_PORT"
            else
                log_error "服务无法绑定到端口 $SERVICE_PORT，请检查日志:"
                journalctl -u movie-recommender.service -n 30
            fi
        fi
    fi
else
    log_warning "未指定服务端口，跳过端口检查"
fi

# 5. 检查防火墙
echo "正在检查防火墙配置..."
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "active"; then
        if ufw status | grep -q "$SERVICE_PORT/tcp"; then
            check_success "防火墙已允许端口 $SERVICE_PORT 通过"
        else
            check_fail "防火墙可能阻止了端口 $SERVICE_PORT"
            if ask_fix; then
                log_info "开放防火墙端口 $SERVICE_PORT..."
                ufw allow $SERVICE_PORT/tcp
                ufw reload
            fi
        fi
    else
        check_success "防火墙未启用，所有端口均可访问"
    fi
elif command -v iptables &> /dev/null; then
    if iptables -L | grep -q "DROP"; then
        log_warning "检测到iptables规则可能阻止端口访问，请检查"
    else
        check_success "未检测到iptables阻止规则"
    fi
else
    log_info "未检测到防火墙软件"
fi

# 6. 检查服务可访问性
echo "正在检查服务可访问性..."
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -n "$SERVER_IP" ] && [ -n "$SERVICE_PORT" ]; then
    # 使用curl或wget检查
    if command -v curl &> /dev/null; then
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP:$SERVICE_PORT/ 2>/dev/null || echo "000")
    elif command -v wget &> /dev/null; then
        RESPONSE=$(wget -qO /dev/null --server-response http://$SERVER_IP:$SERVICE_PORT/ 2>&1 | awk '/HTTP\// {print $2}' | tail -1)
    else
        RESPONSE="000"
        log_warning "无法检查HTTP可访问性，未安装curl或wget"
    fi
    
    if [[ "$RESPONSE" -ge 200 && "$RESPONSE" -lt 400 ]]; then
        check_success "服务可通过 http://$SERVER_IP:$SERVICE_PORT/ 访问，HTTP状态码: $RESPONSE"
    else
        check_fail "服务无法访问，HTTP状态码: $RESPONSE"
        if ask_fix; then
            log_info "尝试重启服务..."
            systemctl restart movie-recommender.service
            log_info "请稍后再次检查可访问性"
        fi
    fi
else
    log_warning "无法检查服务可访问性，缺少IP地址或端口信息"
fi

# 7. 检查日志文件
echo "正在检查日志文件..."
if [ -d "$INSTALL_DIR/logs" ]; then
    check_success "日志目录存在: $INSTALL_DIR/logs"
    # 检查日志目录权限
    LOG_PERM=$(stat -c "%a" "$INSTALL_DIR/logs")
    if [[ "$LOG_PERM" -ge 755 ]]; then
        check_success "日志目录权限正确: $LOG_PERM"
    else
        check_fail "日志目录权限不足: $LOG_PERM (应为755或更高)"
        if ask_fix; then
            log_info "修复日志目录权限..."
            chmod 755 "$INSTALL_DIR/logs"
        fi
    fi
else
    check_fail "日志目录不存在: $INSTALL_DIR/logs"
    if ask_fix; then
        log_info "创建日志目录..."
        mkdir -p "$INSTALL_DIR/logs"
        chmod 755 "$INSTALL_DIR/logs"
    fi
fi

# 8. 检查数据库连接
echo "正在检查数据库连接..."
if [ -f "$CONFIG_FILE" ]; then
    DB_HOST=$(grep "^host" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
    DB_PORT=$(grep "^port" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
    DB_USER=$(grep "^user" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
    DB_PASS=$(grep "^password" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
    DB_NAME=$(grep "^db" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
    
    if [ -n "$DB_HOST" ] && [ -n "$DB_PORT" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASS" ] && [ -n "$DB_NAME" ]; then
        if command -v mysql &> /dev/null; then
            if mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" &>/dev/null; then
                check_success "数据库连接成功"
                # 检查关键表是否存在
                TABLES=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | grep -v "Tables_in")
                if echo "$TABLES" | grep -q "douban_movie"; then
                    check_success "数据库表结构正常"
                else
                    check_fail "缺少关键数据表"
                    if ask_fix; then
                        log_info "尝试初始化数据库..."
                        if [ -f "$INSTALL_DIR/scripts/init_database.sh" ]; then
                            bash "$INSTALL_DIR/scripts/init_database.sh"
                        else
                            log_error "未找到数据库初始化脚本，请手动初始化数据库"
                        fi
                    fi
                fi
            else
                check_fail "数据库连接失败"
                if ask_fix; then
                    log_info "检查MySQL服务状态..."
                    if systemctl is-active --quiet mysql; then
                        log_info "MySQL服务正在运行"
                    else
                        log_info "启动MySQL服务..."
                        systemctl start mysql
                    fi
                    
                    log_info "尝试创建数据库和用户..."
                    if mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS $DB_NAME; GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS'; FLUSH PRIVILEGES;" &>/dev/null; then
                        log_info "数据库和用户创建成功"
                    else
                        log_error "创建数据库和用户失败，请手动配置数据库"
                    fi
                fi
            fi
        else
            log_warning "未安装MySQL客户端，无法检查数据库连接"
        fi
    else
        check_fail "配置文件中缺少数据库连接信息"
    fi
else
    log_warning "未找到配置文件，无法检查数据库连接"
fi

# 9. 提供诊断结果摘要
echo "============================================================"
echo "                  诊断完成"
echo "============================================================"
echo "如需进一步帮助，请运行以下命令查看详细日志:"
echo "  journalctl -u movie-recommender.service -n 100"
echo "或联系电影推荐系统团队获取支持。"
echo "============================================================" 