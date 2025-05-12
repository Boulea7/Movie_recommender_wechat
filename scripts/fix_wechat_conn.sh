#!/bin/bash
# 修复微信公众号连接问题脚本
# 作者：电影推荐系统团队
# 日期：2025-05-13

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

log_section() {
    echo ""
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}>>> $1${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="$INSTALL_DIR/backups"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

# 显示脚本头部
log_section "电影推荐系统微信连接修复脚本"
log_info "开始修复微信公众号连接问题..."

# 1. 检查Nginx反向代理设置
log_section "检查Nginx配置"
if [ -f "/etc/nginx/sites-enabled/movie-recommender" ]; then
    log_info "找到Nginx配置，检查是否正确..."
    # 备份原配置
    cp "/etc/nginx/sites-enabled/movie-recommender" "/etc/nginx/sites-enabled/movie-recommender.bak.$TIMESTAMP"
    
    # 创建新的配置
    cat > "/etc/nginx/sites-enabled/movie-recommender" << EOF
server {
    listen 80;
    server_name _;  # 匹配所有域名
    
    location / {
        proxy_pass http://127.0.0.1:8080;  # 转发到内部端口
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 增加超时设置
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        
        # 确保微信消息正确传递
        client_max_body_size 10m;
    }
    
    # 健康检查端点
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
    
    log_info "验证Nginx配置..."
    nginx -t
    if [ $? -eq 0 ]; then
        log_info "Nginx配置有效，重启Nginx..."
        systemctl restart nginx
        log_info "Nginx已重启"
    else
        log_error "Nginx配置无效，恢复原配置..."
        mv "/etc/nginx/sites-enabled/movie-recommender.bak.$TIMESTAMP" "/etc/nginx/sites-enabled/movie-recommender"
        nginx -t && systemctl restart nginx
    fi
else
    log_warning "未找到Nginx配置，创建新配置..."
    
    # 安装Nginx（如果未安装）
    if ! command -v nginx &> /dev/null; then
        log_info "安装Nginx..."
        apt-get update
        apt-get install -y nginx
    fi
    
    # 创建配置
    cat > "/etc/nginx/sites-available/movie-recommender" << EOF
server {
    listen 80;
    server_name _;  # 匹配所有域名
    
    location / {
        proxy_pass http://127.0.0.1:8080;  # 转发到内部端口
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 增加超时设置
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        
        # 确保微信消息正确传递
        client_max_body_size 10m;
    }
    
    # 健康检查端点
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
    
    # 启用配置
    ln -sf "/etc/nginx/sites-available/movie-recommender" "/etc/nginx/sites-enabled/"
    
    # 验证并重启
    nginx -t && systemctl restart nginx
    log_info "Nginx配置已创建并启用"
fi

# 2. 修改服务配置，将端口改为8080
log_section "修改服务配置"
if [ -f "$INSTALL_DIR/config/database.conf" ]; then
    log_info "修改服务端口为8080..."
    
    # 备份配置文件
    cp "$INSTALL_DIR/config/database.conf" "$BACKUP_DIR/database.conf.bak.$TIMESTAMP"
    
    # 修改端口
    sed -i 's/^port = 80/port = 8080/' "$INSTALL_DIR/config/database.conf"
    log_info "服务端口已修改为8080"
else
    log_warning "找不到配置文件，创建新配置..."
    
    mkdir -p "$INSTALL_DIR/config"
    cat > "$INSTALL_DIR/config/database.conf" << EOF
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
port = 8080
token = HelloMovieRecommender
encoding_key = X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a
debug = false
log_level = INFO

[recommender]
similarity_threshold = 0.5
min_ratings = 3
max_recommendations = 10
EOF
    
    log_info "已创建新配置文件，端口设置为8080"
fi

# 3. 修改服务文件
log_section "更新服务文件"
if [ -f "/etc/systemd/system/movie-recommender.service" ]; then
    log_info "更新服务文件..."
    
    # 备份服务文件
    cp "/etc/systemd/system/movie-recommender.service" "/etc/systemd/system/movie-recommender.service.bak.$TIMESTAMP"
    
    # 获取正确的Python路径
    PYTHON_PATH=$(grep -o "ExecStart=.*python" "/etc/systemd/system/movie-recommender.service" | head -1 | awk '{print $1}' | cut -d'=' -f2)
    
    if [ -z "$PYTHON_PATH" ]; then
        # 如果找不到路径，使用默认虚拟环境路径
        if [ -d "$INSTALL_DIR/venv" ]; then
            PYTHON_PATH="$INSTALL_DIR/venv/bin/python"
        else
            PYTHON_PATH=$(which python3)
        fi
        log_info "使用默认Python解释器路径: $PYTHON_PATH"
    fi
    
    # 更新服务文件
    cat > "/etc/systemd/system/movie-recommender.service" << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment="PYTHONPATH=$INSTALL_DIR"
ExecStart=$PYTHON_PATH $INSTALL_DIR/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载并重启服务
    log_info "重载systemd配置..."
    systemctl daemon-reload
    log_info "重启服务..."
    systemctl restart movie-recommender.service
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet movie-recommender.service; then
        log_info "服务已成功启动！"
    else
        log_warning "服务可能未正确启动，查看状态："
        systemctl status movie-recommender.service --no-pager
    fi
else
    log_warning "找不到服务文件，跳过服务更新"
fi

# 4. 添加基本错误处理
log_section "添加重定向错误处理"
if [ -f "$INSTALL_DIR/web_server/main.py" ]; then
    log_info "修改main.py添加重定向错误处理..."
    
    # 备份原始文件
    cp "$INSTALL_DIR/web_server/main.py" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"
    
    # 检查是否已有错误处理
    if ! grep -q "handle_redirect_error" "$INSTALL_DIR/web_server/main.py"; then
        # 在适当位置添加错误处理函数
        TEMP_FILE=$(mktemp)
        awk '{print} /class Main\(object\):/ {print "\tdef handle_redirect_error(self):\n\t\tweb.ctx.status = \"200 OK\"\n\t\treturn \"success\""}' "$INSTALL_DIR/web_server/main.py" > "$TEMP_FILE"
        
        # 添加错误处理逻辑到POST方法
        sed -i 's/except Exception as e:/except Exception as e:\n\t\t\treturn self.handle_redirect_error()\n\t\ttry:/' "$TEMP_FILE"
        
        # 替换原始文件
        mv "$TEMP_FILE" "$INSTALL_DIR/web_server/main.py"
        chmod 644 "$INSTALL_DIR/web_server/main.py"
        log_info "已添加重定向错误处理"
    else
        log_info "文件已包含重定向错误处理，跳过修改"
    fi
else
    log_warning "找不到main.py文件，跳过错误处理修改"
fi

# 5. 检查防火墙设置
log_section "检查防火墙设置"
if command -v ufw &> /dev/null; then
    log_info "检查UFW防火墙设置..."
    
    # 确保80端口开放
    ufw status | grep "80/tcp" || {
        log_info "开放80端口..."
        ufw allow 80/tcp
        log_info "防火墙规则已更新"
    }
    
    # 如果防火墙已启用，则重载规则
    ufw status | grep -q "Status: active" && {
        log_info "重载防火墙规则..."
        ufw reload
    }
elif command -v firewall-cmd &> /dev/null; then
    log_info "检查firewalld防火墙设置..."
    
    # 确保80端口开放
    firewall-cmd --list-ports | grep "80/tcp" || {
        log_info "开放80端口..."
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --reload
        log_info "防火墙规则已更新"
    }
else
    log_info "未检测到支持的防火墙系统，跳过防火墙配置"
fi

# 6. 添加健康检查端点
log_section "添加健康检查端点"
if [ -f "$INSTALL_DIR/web_server/main.py" ]; then
    log_info "添加健康检查端点到main.py..."
    
    # 检查是否已有健康检查
    if ! grep -q "class Health" "$INSTALL_DIR/web_server/main.py"; then
        # 添加健康检查类
        TEMP_FILE=$(mktemp)
        
        # 修改URL配置
        sed 's|urls = (|urls = (\n\t\x27/health\x27, \x27Health\x27,|' "$INSTALL_DIR/web_server/main.py" > "$TEMP_FILE"
        
        # 添加健康检查类
        awk '{print} /class Main\(object\):/ {print "class Health(object):\n\tdef GET(self):\n\t\tweb.header(\x27Content-Type\x27, \x27text/plain\x27)\n\t\treturn \x27OK\x27\n"}' "$TEMP_FILE" > "$INSTALL_DIR/web_server/main.py"
        
        chmod 644 "$INSTALL_DIR/web_server/main.py"
        log_info "已添加健康检查端点"
    else
        log_info "文件已包含健康检查端点，跳过修改"
    fi
else
    log_warning "找不到main.py文件，跳过健康检查端点添加"
fi

# 7. 修复数据库连接问题
log_section "修复数据库连接问题"
log_info "检查数据库连接和权限..."

# 测试数据库连接
MYSQL_USER=$(grep -o "user = [^,]*" "$INSTALL_DIR/config/database.conf" | awk '{print $3}')
MYSQL_PASSWORD=$(grep -o "password = [^,]*" "$INSTALL_DIR/config/database.conf" | awk '{print $3}')
MYSQL_DB=$(grep -o "db = [^,]*" "$INSTALL_DIR/config/database.conf" | awk '{print $3}')

if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$MYSQL_DB" ]; then
    log_warning "无法从配置中获取数据库信息"
else
    log_info "检查数据库连接..."
    # 尝试连接数据库
    mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "USE $MYSQL_DB; SELECT 1;" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_info "数据库连接正常！"
    else
        log_warning "数据库连接失败，尝试修复权限..."
        
        # 尝试使用root修复权限（需要root密码）
        log_info "请输入MySQL root密码："
        read -s MYSQL_ROOT_PASSWORD
        
        # 创建用户并授权
        mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'; GRANT ALL PRIVILEGES ON $MYSQL_DB.* TO '$MYSQL_USER'@'localhost'; FLUSH PRIVILEGES;" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log_info "数据库用户和权限已修复！"
        else
            log_error "无法修复数据库权限，请手动检查数据库配置"
        fi
    fi
fi

# 8. 重启所有服务
log_section "重启服务"
log_info "重启Nginx..."
systemctl restart nginx

log_info "重启电影推荐系统服务..."
systemctl restart movie-recommender.service

# 等待服务启动
log_info "等待服务启动..."
sleep 5

# 9. 测试连接
log_section "测试连接"
log_info "测试HTTP连接..."

# 获取服务器IP
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="localhost"
fi

# 测试连接
curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP/health"
HEALTH_STATUS=$?

if [ $HEALTH_STATUS -eq 200 ]; then
    log_info "健康检查成功！HTTP状态为200"
else
    log_warning "健康检查返回非200状态码: $HEALTH_STATUS"
    
    # 尝试通过内部端口直接访问
    curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8080/health"
    DIRECT_STATUS=$?
    
    if [ $DIRECT_STATUS -eq 200 ]; then
        log_info "直接访问服务成功，但Nginx代理可能有问题"
    else
        log_warning "直接访问服务也失败，可能是应用程序问题"
    fi
fi

# 修复完成
log_section "修复完成"
log_info "微信公众号连接问题修复脚本已完成"
log_info "如果问题仍然存在，请尝试以下操作："
log_info "1. 检查微信公众号服务器配置，确保URL和Token正确"
log_info "2. 测试连接: curl -v http://$SERVER_IP/"
log_info "3. 查看错误日志: tail -f $INSTALL_DIR/logs/web_server.log"
log_info "4. 检查服务状态: systemctl status movie-recommender.service"
log_info "5. 检查Nginx状态: systemctl status nginx" 