#!/bin/bash
# 电影推荐系统自动部署脚本
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

# 检查依赖
check_dependency() {
    if ! command -v $1 &> /dev/null; then
        log_warning "$1 未安装，正在安装..."
        apt-get update
        apt-get install -y $1
        if [ $? -ne 0 ]; then
            log_error "安装 $1 失败！"
            exit 1
        fi
    fi
}

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="/opt/recommender_backups"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')
PORT=${PORT:-80}
CURRENT_DIR=$(pwd)

# 脚本开始
log_info "开始部署电影推荐系统..."
log_info "项目目录: $CURRENT_DIR"
log_info "安装目录: $INSTALL_DIR"

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

# 添加脚本分段标记
log_section() {
    echo ""
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}>>> $1${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# 检查系统依赖
log_section "检查系统依赖"
log_info "检查系统依赖..."
check_dependency python3
check_dependency python3-pip
check_dependency python3-venv
check_dependency mysql-client
check_dependency libmysqlclient-dev
check_dependency libcap2-bin

# 创建安装目录
log_info "创建安装目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BACKUP_DIR"

# 备份现有安装
if [ -d "$INSTALL_DIR" ] && [ "$(ls -A $INSTALL_DIR)" ]; then
    BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"
    log_info "备份现有安装到 $BACKUP_PATH..."
    mkdir -p "$BACKUP_PATH"
    cp -R "$INSTALL_DIR"/* "$BACKUP_PATH" 2>/dev/null || true
fi

# 安装系统级依赖
log_section "安装系统依赖"
log_info "安装系统依赖..."
apt-get update
apt-get install -y python3 python3-pip python3-venv mysql-client libmysqlclient-dev libcap2-bin

# 复制项目文件到安装目录
log_section "复制项目文件"
log_info "复制项目文件到安装目录..."
cp -R ./* "$INSTALL_DIR"

# 创建日志目录
log_info "创建日志目录..."
mkdir -p "$INSTALL_DIR/logs"

# 创建Python虚拟环境
log_info "创建Python虚拟环境..."
if [ ! -d "$INSTALL_DIR/venv" ]; then
    python3 -m venv "$INSTALL_DIR/venv"
fi

# 安装Python依赖
log_info "安装Python依赖..."
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

# 设置脚本执行权限
log_info "设置脚本执行权限..."
chmod +x "$INSTALL_DIR/scripts/"*.sh
chmod +x "$INSTALL_DIR/data_spider/"*.py
chmod +x "$INSTALL_DIR/web_server/"*.py

# 初始化MySQL服务
log_info "检查和初始化MySQL服务..."
if [ -f "$INSTALL_DIR/scripts/init_mysql.sh" ]; then
    cd "$INSTALL_DIR"
    bash "$INSTALL_DIR/scripts/init_mysql.sh"
    if [ $? -ne 0 ]; then
        log_error "MySQL服务初始化失败，请检查错误并修复"
        log_info "您可以手动运行 bash $INSTALL_DIR/scripts/init_mysql.sh 查看详细错误"
    fi
fi

# 初始化数据库
log_info "初始化数据库..."
cd "$INSTALL_DIR"
bash "$INSTALL_DIR/scripts/init_database.sh"

# 在配置文件中设置正确的端口
log_info "配置服务端口..."
CONFIG_FILE="$INSTALL_DIR/config/database.conf"
if [ -f "$CONFIG_FILE" ]; then
    # 检查配置文件格式
    if grep -q "^\[service\]" "$CONFIG_FILE"; then
        # 更新端口配置
        if grep -q "^port" "$CONFIG_FILE"; then
            sed -i "s/^port = .*/port = $PORT/" "$CONFIG_FILE"
        else
            # 如果没有port配置项，添加到[service]部分
            sed -i "/^\[service\]/a port = $PORT" "$CONFIG_FILE"
        fi
    else
        log_warning "配置文件格式不正确，请手动设置端口"
    fi
else
    log_warning "配置文件不存在，将创建默认配置"
    mkdir -p "$INSTALL_DIR/config"
    cat > "$CONFIG_FILE" << EOF
[database]
host = localhost
port = 3306
user = douban_user
password = MySQL_20050816Zln@233
db = douban
charset = utf8mb4

[service]
port = $PORT
token = HelloMovieRecommender
encoding_key = X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a
debug = false
log_level = INFO

[recommender]
similarity_threshold = 0.5
min_ratings = 3
max_recommendations = 10
EOF
fi

# 创建系统服务
log_info "创建系统服务..."
cat > /etc/systemd/system/movie-recommender.service << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender

[Install]
WantedBy=multi-user.target
EOF

# 重载系统服务
log_info "重载系统服务..."
systemctl daemon-reload

# 如果端口小于1024，添加CAP_NET_BIND_SERVICE权限
if [ "$PORT" -lt 1024 ]; then
    log_info "设置低端口绑定权限..."
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/venv/bin/python3"
    # 检查是否成功设置
    if [ $? -ne 0 ]; then
        log_warning "设置CAP_NET_BIND_SERVICE权限失败，将改用端口8080并配置Nginx"
        sed -i "s/^port = .*/port = 8080/" "$CONFIG_FILE"
        log_info "将在后续步骤中配置Nginx作为反向代理"
    else
        log_info "成功设置CAP_NET_BIND_SERVICE权限，可以绑定低端口"
    fi
fi

# 启动电影推荐系统服务
log_info "启动电影推荐系统服务..."
systemctl enable movie-recommender.service
systemctl start movie-recommender.service

# 验证服务是否启动成功
MAX_ATTEMPTS=3
ATTEMPT=1
SUCCESS=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    log_warning "服务启动中，尝试 $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 3
    
    if systemctl is-active --quiet movie-recommender.service; then
        SUCCESS=true
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$SUCCESS" = false ]; then
    log_error "电影推荐系统服务启动失败，请检查日志"
    systemctl status movie-recommender.service
    
    # 检查日志以确定失败原因
    log_info "正在检查日志以确定失败原因..."
    journalctl -u movie-recommender.service -n 30 --no-pager
    
    # 检查是否是缺少web.py模块导致的
    if journalctl -u movie-recommender.service | grep -q "No module named 'web'"; then
        log_warning "缺少web.py模块，尝试修复..."
        "$INSTALL_DIR/venv/bin/pip" install web.py
        systemctl restart movie-recommender.service
        sleep 3
        
        if systemctl is-active --quiet movie-recommender.service; then
            log_info "服务已成功启动！"
            SUCCESS=true
        fi
    fi
    
    # 检查是否是配置解析错误
    if journalctl -u movie-recommender.service | grep -q "get_section"; then
        log_warning "配置解析错误，尝试修复config_parser.py..."
        # 检查是否已修复
        if grep -q "get_section" "$INSTALL_DIR/web_server/config_parser.py"; then
            log_info "config_parser.py已包含get_section方法，重启服务..."
            systemctl restart movie-recommender.service
            sleep 3
            
            if systemctl is-active --quiet movie-recommender.service; then
                log_info "服务已成功启动！"
                SUCCESS=true
            fi
        fi
    fi
    
    if [ "$SUCCESS" = false ]; then
        log_error "无法自动修复服务启动问题，请手动检查"
    fi
fi

# 检查80端口占用情况
log_info "检查80端口占用情况..."
PORT80_OCCUPIED=false
if netstat -tuln | grep -q ":80 "; then
    if ! systemctl is-active --quiet movie-recommender.service; then
        log_warning "80端口被占用，且电影推荐系统服务未成功启动"
        log_info "将尝试使用Nginx作为反向代理..."
        PORT80_OCCUPIED=true
    fi
fi

# 如果端口被占用，使用Nginx作为反向代理
if [ "$PORT80_OCCUPIED" = true ] || [ "$PORT" -ne 80 ]; then
    log_info "配置Nginx反向代理..."
    if [ -f "$INSTALL_DIR/scripts/setup_nginx.sh" ]; then
        bash "$INSTALL_DIR/scripts/setup_nginx.sh"
    else
        log_warning "找不到Nginx配置脚本，请手动配置Nginx"
    fi
fi

# 检查防火墙设置
log_info "检查防火墙设置..."
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    log_info "防火墙已启用，确保80端口开放..."
    ufw allow 80/tcp || true
    ufw reload || true
fi

# 添加自动修复功能
log_section "运行自动修复脚本"
log_info "修复已知的系统问题..."

# 1. 修复data_spider/create_target_table.py中的Try-Except-Finally问题
log_info "修复 data_spider/create_target_table.py 中的Try-Except-Finally问题..."
if [ -f "$INSTALL_DIR/data_spider/create_target_table.py" ]; then
    # 备份原始文件
    mkdir -p "$BACKUP_DIR"
    cp "$INSTALL_DIR/data_spider/create_target_table.py" "$BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"
    
    # 修复MySQLdb导入
    sed -i 's/import MySQLdb/import pymysql as MySQLdb/' "$INSTALL_DIR/data_spider/create_target_table.py"
    
    # 安装pymysql依赖
    if [ -d "$INSTALL_DIR/venv" ]; then
        "$INSTALL_DIR/venv/bin/pip" install pymysql
    else
        pip install pymysql
    fi
    
    log_info "data_spider/create_target_table.py 修复完成"
else
    log_warning "找不到 data_spider/create_target_table.py 文件，跳过修复"
fi

# 2. 修复web_server/main.py中的缩进问题
log_info "修复 web_server/main.py 中的缩进问题..."
if [ -f "$INSTALL_DIR/web_server/main.py" ]; then
    # 备份原始文件
    cp "$INSTALL_DIR/web_server/main.py" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"
    
    # 查找update_user_info方法的位置
    LINE_START=$(grep -n "def update_user_info" "$INSTALL_DIR/web_server/main.py" | cut -d: -f1)
    if [ -n "$LINE_START" ]; then
        log_info "找到update_user_info方法，行号: $LINE_START"
        
        # 创建临时文件
        TMP_FILE=$(mktemp)
        
        # 提取文件头部
        head -n $((LINE_START-1)) "$INSTALL_DIR/web_server/main.py" > "$TMP_FILE"
        
        # 添加修复后的update_user_info方法
        cat >> "$TMP_FILE" << 'EOF'
	def update_user_info(self, user_name):
		try:
			self.db = pymysql.connect(
				host=DB_CONFIG.get('host', 'localhost'),
				port=int(DB_CONFIG.get('port', 3306)),
				user=DB_CONFIG.get('user', 'douban_user'),
				password=DB_CONFIG.get('password', 'MySQL_20050816Zln@233'),
				db=DB_CONFIG.get('db', 'douban'),
				charset=DB_CONFIG.get('charset', 'utf8mb4')
			)
			self.cursor = self.db.cursor()
			cmd = 'select * from user_info where wx_id = "{}";'.format(user_name)
			self.cursor.execute(cmd)
			results = self.cursor.fetchall()
			if len(results) == 0:
				cmd = 'insert into user_info(wx_id, start_time) values("{}", "{}");'.format(user_name, int(time.time()))
				try:
					self.cursor.execute(cmd)
					self.db.commit()
					logger.info(f"添加新用户: {user_name}")
				except Exception as e:
					self.db.rollback()
					logger.error(f"添加用户失败: {e}")
		except Exception as e:
			logger.error(f"更新用户信息失败: {e}")
EOF
        
        # 查找下一个方法的位置
        LINE_END=$(tail -n +$((LINE_START+1)) "$INSTALL_DIR/web_server/main.py" | grep -n "^	def " | head -1 | cut -d: -f1)
        if [ -z "$LINE_END" ]; then
            log_warning "无法找到下一个方法，尝试其他方式..."
            LINE_END=$(grep -n "^	def " "$INSTALL_DIR/web_server/main.py" | sort -n | awk -v start=$LINE_START '$1 > start {print $1; exit}' | cut -d: -f1)
        fi
        
        if [ -n "$LINE_END" ]; then
            LINE_END=$((LINE_START + LINE_END))
            
            # 添加文件剩余部分
            tail -n +$((LINE_END)) "$INSTALL_DIR/web_server/main.py" >> "$TMP_FILE"
            
            # 替换原始文件
            mv "$TMP_FILE" "$INSTALL_DIR/web_server/main.py"
            chmod 644 "$INSTALL_DIR/web_server/main.py"
            
            log_info "web_server/main.py 缩进问题修复完成"
        else
            log_error "无法确定main.py中下一个方法的位置，跳过修复"
            rm "$TMP_FILE"
        fi
    else
        log_warning "在main.py中找不到update_user_info方法，跳过修复"
    fi
else
    log_warning "找不到 web_server/main.py 文件，跳过修复"
fi

# 3. 修复缺少MySQLdb模块的问题
log_info "安装缺失的Python依赖..."
if [ -d "$INSTALL_DIR/venv" ]; then
    "$INSTALL_DIR/venv/bin/pip" install pymysql
    # 添加MySQLdb到pymysql的兼容性别名
    cat > "$INSTALL_DIR/web_server/mysqldb_wrapper.py" << 'EOF'
"""
MySQLdb兼容性包装器，使用pymysql作为替代方案
当无法安装原生MySQLdb时使用此模块
"""
import pymysql
import sys

# 将pymysql设置为MySQLdb的别名
sys.modules['MySQLdb'] = pymysql
EOF
    log_info "已创建MySQLdb兼容性包装器"
else
    log_warning "找不到虚拟环境，尝试在系统级别安装依赖"
    pip install pymysql
fi

# 4. 修复端口绑定权限问题
log_info "修复端口绑定权限问题..."
if [ -f "/etc/systemd/system/movie-recommender.service" ]; then
    # 添加端口绑定权限到服务文件
    grep -q "AmbientCapabilities=CAP_NET_BIND_SERVICE" "/etc/systemd/system/movie-recommender.service" || {
        sed -i '/\[Service\]/a AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE' "/etc/systemd/system/movie-recommender.service"
        log_info "已添加端口绑定权限到服务文件"
    }
    
    # 获取Python解释器路径
    PYTHON_PATH=$(grep -o "ExecStart=.*python" "/etc/systemd/system/movie-recommender.service" | awk '{print $1}' | cut -d'=' -f2)
    
    if [ -z "$PYTHON_PATH" ]; then
        if [ -d "$INSTALL_DIR/venv" ]; then
            PYTHON_PATH="$INSTALL_DIR/venv/bin/python"
        else
            PYTHON_PATH=$(which python3)
        fi
        log_info "使用默认Python解释器路径: $PYTHON_PATH"
    fi
    
    # 检查Python解释器是否是符号链接并设置权限
    if [ -L "$PYTHON_PATH" ]; then
        log_info "Python解释器是符号链接，查找真实路径..."
        REAL_PYTHON_PATH=$(readlink -f "$PYTHON_PATH")
        log_info "真实路径: $REAL_PYTHON_PATH"
        setcap 'cap_net_bind_service=+ep' "$REAL_PYTHON_PATH"
    else
        log_info "Python解释器不是符号链接，直接设置权限..."
        setcap 'cap_net_bind_service=+ep' "$PYTHON_PATH"
    fi
    
    if [ $? -ne 0 ]; then
        log_warning "设置权限失败，安装authbind作为备选方案..."
        apt-get install -y authbind
        touch /etc/authbind/byport/80
        chmod 500 /etc/authbind/byport/80
        chown root /etc/authbind/byport/80
        
        # 修改服务文件使用authbind
        sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/authbind --deep $PYTHON_PATH $INSTALL_DIR/web_server/main.py|" "/etc/systemd/system/movie-recommender.service"
        log_info "已配置authbind作为备选方案"
    else
        log_info "成功设置端口绑定权限"
    fi
    
    systemctl daemon-reload
else
    log_warning "找不到服务配置文件，跳过端口绑定权限修复"
fi

log_info "所有自动修复完成"

# 部署完成
log_info "部署完成！可以通过以下命令查看服务状态："
log_info "systemctl status movie-recommender.service"
log_info "可以通过以下命令查看日志："
log_info "journalctl -u movie-recommender.service -f"
log_info "安装目录: $INSTALL_DIR"

# 获取服务器IP
SERVER_IP=$(hostname -I | awk '{print $1}')

log_info "----------------------------------------------------------------"
log_info "部署后操作建议:"
log_info "1. 访问 http://$SERVER_IP 测试服务"
log_info "2. 如遇80端口问题，可运行: sudo bash $INSTALL_DIR/scripts/setup_nginx.sh"
log_info "3. 配置微信公众号URL: http://$SERVER_IP"
log_info "4. 配置微信公众号Token: 见 $INSTALL_DIR/config/database.conf 的token值"
log_info "----------------------------------------------------------------" 