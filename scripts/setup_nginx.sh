#!/bin/bash
# 电影推荐系统Nginx反向代理配置脚本
# 作者：电影推荐系统团队
# 日期：2025-05-10

set -e  # 遇到错误立即退出

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

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
TIMESTAMP=$(date '+%Y%m%d%H%M%S')
APP_PORT=${APP_PORT:-8080}
SERVER_NAME=${SERVER_NAME:-"_"}  # 默认匹配所有域名/IP
VENV_DIR="$INSTALL_DIR/venv"
SERVICE_FILE="/etc/systemd/system/movie-recommender.service"

# 创建日志目录
mkdir -p "$INSTALL_DIR/logs"
LOG_FILE="$INSTALL_DIR/logs/nginx_setup_${TIMESTAMP}.log"

log_info "开始配置Nginx反向代理..." | tee -a "$LOG_FILE"

# 检查Nginx是否已安装
if ! command -v nginx &> /dev/null; then
    log_info "Nginx未安装，开始安装..." | tee -a "$LOG_FILE"
    apt update | tee -a "$LOG_FILE"
    apt install -y nginx | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_error "Nginx安装失败，请手动检查安装错误" | tee -a "$LOG_FILE"
        exit 1
    fi
else
    log_info "Nginx已安装" | tee -a "$LOG_FILE"
fi

# 检查是否有电影推荐系统配置文件
if [ ! -f "$INSTALL_DIR/config/database.conf" ]; then
    log_error "找不到配置文件: $INSTALL_DIR/config/database.conf" | tee -a "$LOG_FILE"
    log_error "请确保电影推荐系统已正确安装" | tee -a "$LOG_FILE"
    exit 1
fi

# 修改电影推荐系统配置，使用8080端口
log_info "配置电影推荐系统使用端口 $APP_PORT..." | tee -a "$LOG_FILE"
sed -i "s/port = .*/port = $APP_PORT/" "$INSTALL_DIR/config/database.conf" | tee -a "$LOG_FILE"

# 更新systemd服务文件以使用虚拟环境(如果存在)
if [ -f "$SERVICE_FILE" ]; then
    log_info "更新systemd服务配置以使用正确的端口..." | tee -a "$LOG_FILE"
    
    # 检查虚拟环境是否存在
    if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/python" ]; then
        log_info "检测到Python虚拟环境，更新服务配置..." | tee -a "$LOG_FILE"
        sed -i "s|ExecStart=.*|ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/web_server/main.py|" "$SERVICE_FILE"
    fi
else
    log_warning "未找到系统服务文件，将尝试创建..." | tee -a "$LOG_FILE"
    
    if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/python" ]; then
        PYTHON_PATH="$VENV_DIR/bin/python"
    else
        PYTHON_PATH="/usr/bin/python3"
    fi
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$PYTHON_PATH $INSTALL_DIR/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender

[Install]
WantedBy=multi-user.target
EOF
    
    log_info "已创建服务文件，重载systemd配置..." | tee -a "$LOG_FILE"
    systemctl daemon-reload
fi

# 检查80端口是否被占用
PORT80_PID=$(netstat -tuln | grep -w ":80" | awk '{print $7}' | cut -d'/' -f1)
if [ -n "$PORT80_PID" ]; then
    PORT80_PROCESS=$(ps -p $PORT80_PID -o comm=)
    if [ "$PORT80_PROCESS" != "nginx" ]; then
        log_warning "80端口被 $PORT80_PROCESS 进程占用，可能会导致Nginx无法正常启动" | tee -a "$LOG_FILE"
        read -p "是否尝试停止占用80端口的进程? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "尝试停止进程 $PORT80_PROCESS (PID: $PORT80_PID)..." | tee -a "$LOG_FILE"
            kill -15 $PORT80_PID || log_warning "无法停止进程，可能需要手动处理" | tee -a "$LOG_FILE"
            sleep 2
        fi
    else
        log_info "80端口已被Nginx占用，将继续配置" | tee -a "$LOG_FILE"
    fi
fi

# 创建Nginx配置文件
log_info "创建Nginx配置文件..." | tee -a "$LOG_FILE"
cat > /etc/nginx/sites-available/recommender << EOF
server {
    listen 80;
    server_name $SERVER_NAME;

    access_log /var/log/nginx/recommender_access.log;
    error_log /var/log/nginx/recommender_error.log;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 增加超时时间
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        
        # WebSocket支持（如果需要）
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# 检查是否有默认配置，可能会和我们的配置冲突
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    log_info "禁用Nginx默认配置..." | tee -a "$LOG_FILE"
    rm -f /etc/nginx/sites-enabled/default
fi

# 启用配置
log_info "启用Nginx配置..." | tee -a "$LOG_FILE"
ln -sf /etc/nginx/sites-available/recommender /etc/nginx/sites-enabled/ | tee -a "$LOG_FILE"

# 测试Nginx配置
log_info "测试Nginx配置..." | tee -a "$LOG_FILE"
nginx_test=$(nginx -t 2>&1)
if [ $? -ne 0 ]; then
    log_error "Nginx配置测试失败: $nginx_test" | tee -a "$LOG_FILE"
    log_error "请手动检查Nginx配置，修复问题后重试" | tee -a "$LOG_FILE"
    exit 1
else
    log_info "Nginx配置测试成功" | tee -a "$LOG_FILE"
fi

# 重启Nginx
log_info "重启Nginx..." | tee -a "$LOG_FILE"
systemctl restart nginx | tee -a "$LOG_FILE"
if [ $? -ne 0 ]; then
    log_error "Nginx重启失败，请检查Nginx状态" | tee -a "$LOG_FILE"
    systemctl status nginx | tee -a "$LOG_FILE"
    exit 1
fi

# 确保Nginx开机自启
log_info "设置Nginx开机自启..." | tee -a "$LOG_FILE"
systemctl enable nginx | tee -a "$LOG_FILE"

# 重载systemd配置
log_info "重载systemd配置..." | tee -a "$LOG_FILE"
systemctl daemon-reload | tee -a "$LOG_FILE"

# 重启电影推荐系统服务
log_info "重启电影推荐系统服务..." | tee -a "$LOG_FILE"
systemctl restart movie-recommender.service | tee -a "$LOG_FILE"
if [ $? -ne 0 ]; then
    log_error "电影推荐系统服务重启失败，请检查服务状态" | tee -a "$LOG_FILE"
    systemctl status movie-recommender.service | tee -a "$LOG_FILE"
    log_info "检查日志以获取更多信息: journalctl -u movie-recommender.service -n 30" | tee -a "$LOG_FILE"
    # 尝试用调试模式启动
    log_info "尝试手动启动服务以查看错误..." | tee -a "$LOG_FILE"
    if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/python" ]; then
        cd "$INSTALL_DIR" && "$VENV_DIR/bin/python" web_server/main.py 2>&1 | head -20 | tee -a "$LOG_FILE"
    else
        cd "$INSTALL_DIR" && python3 web_server/main.py 2>&1 | head -20 | tee -a "$LOG_FILE"
    fi
    exit 1
fi

# 确保电影推荐系统服务开机自启
log_info "设置电影推荐系统服务开机自启..." | tee -a "$LOG_FILE"
systemctl enable movie-recommender.service | tee -a "$LOG_FILE"

# 检查服务状态
sleep 3
nginx_status=$(systemctl is-active nginx)
app_status=$(systemctl is-active movie-recommender.service)

log_info "Nginx服务状态: $nginx_status" | tee -a "$LOG_FILE"
log_info "电影推荐系统服务状态: $app_status" | tee -a "$LOG_FILE"

if [ "$nginx_status" = "active" ] && [ "$app_status" = "active" ]; then
    log_info "配置完成！微信公众号可以通过80端口访问电影推荐系统" | tee -a "$LOG_FILE"
    log_info "电影推荐系统运行在端口 $APP_PORT，Nginx反向代理转发到80端口" | tee -a "$LOG_FILE"
    
    # 获取服务器IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    log_info "微信公众号配置URL: http://$SERVER_IP/" | tee -a "$LOG_FILE"
    
    # 尝试测试连接
    log_info "测试连接..." | tee -a "$LOG_FILE"
    if command -v curl &> /dev/null; then
        curl_result=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
        log_info "HTTP状态码: $curl_result" | tee -a "$LOG_FILE"
        if [ "$curl_result" -ge 200 ] && [ "$curl_result" -lt 400 ]; then
            log_info "HTTP测试成功!" | tee -a "$LOG_FILE"
        else
            log_warning "HTTP测试返回非成功状态码，可能需要进一步排查" | tee -a "$LOG_FILE"
        fi
    else
        log_warning "未安装curl，跳过连接测试" | tee -a "$LOG_FILE"
    fi
else
    log_error "配置过程中出现问题，请检查日志" | tee -a "$LOG_FILE"
fi

# 检查防火墙设置
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "active"; then
        log_info "检测到防火墙已启用，确保80端口开放..." | tee -a "$LOG_FILE"
        ufw allow 80/tcp | tee -a "$LOG_FILE" || true
        ufw reload | tee -a "$LOG_FILE" || true
    fi
fi

# 检查端口监听情况
log_info "检查端口监听情况..." | tee -a "$LOG_FILE"
if command -v netstat &> /dev/null; then
    netstat -tuln | grep -E ":80|:$APP_PORT" | tee -a "$LOG_FILE"
elif command -v ss &> /dev/null; then
    ss -tuln | grep -E ":80|:$APP_PORT" | tee -a "$LOG_FILE"
else
    log_warning "未安装netstat或ss，无法检查端口" | tee -a "$LOG_FILE"
fi

log_info "完成！配置日志保存在 $LOG_FILE" | tee -a "$LOG_FILE"
log_info "===================================================="
log_info "部署摘要:"
log_info "1. 电影推荐系统运行在端口: $APP_PORT"
log_info "2. Nginx反向代理将80端口请求转发到: $APP_PORT"
log_info "3. 微信公众号URL配置: http://$SERVER_IP/"
log_info "4. 配置文件位置: $INSTALL_DIR/config/database.conf"
log_info "5. 日志位置:"
log_info "   - 系统服务日志: journalctl -u movie-recommender.service -f"
log_info "   - 应用日志: $INSTALL_DIR/logs/web_server.log"
log_info "   - Nginx访问日志: /var/log/nginx/recommender_access.log"
log_info "   - Nginx错误日志: /var/log/nginx/recommender_error.log"
log_info "====================================================" | tee -a "$LOG_FILE" 