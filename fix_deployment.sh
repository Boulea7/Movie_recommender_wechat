#!/bin/bash
# 电影推荐系统部署修复脚本
# 作者：电影推荐系统团队
# 日期：2025-05-13
# 
# 此脚本用于修复部署过程中可能出现的问题，包括：
# 1. 日志目录问题：创建正确的日志目录并修复路径引用
# 2. Python缩进问题：修复main.py中的update_user_info和on_event方法的缩进
# 3. Python依赖问题：修复MySQLdb导入与兼容性
# 4. 端口绑定权限问题：为Python解释器添加低端口绑定权限

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
log_section "电影推荐系统部署修复脚本"
log_info "开始修复系统中的所有已知问题..."

# 确保安装和备份目录存在
mkdir -p "$INSTALL_DIR"
mkdir -p "$BACKUP_DIR"

# 1. 确保日志目录存在
log_section "创建日志目录"
mkdir -p "$INSTALL_DIR/logs"
chmod 755 "$INSTALL_DIR/logs"
log_info "已创建日志目录: $INSTALL_DIR/logs"

# 2. 修复data_spider/create_target_table.py中的日志路径问题
log_section "修复data_spider/create_target_table.py"
if [ -f "$INSTALL_DIR/data_spider/create_target_table.py" ]; then
    # 备份原始文件
    cp "$INSTALL_DIR/data_spider/create_target_table.py" "$BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"
    log_info "已备份原始文件到 $BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"
    
    # 创建临时文件
    TEMP_FILE=$(mktemp)
    
    # 修复MySQLdb导入
    log_info "修复MySQLdb导入为pymysql..."
    if grep -q "import MySQLdb" "$INSTALL_DIR/data_spider/create_target_table.py"; then
        sed 's/import MySQLdb/import pymysql as MySQLdb/' "$INSTALL_DIR/data_spider/create_target_table.py" > "$TEMP_FILE"
        log_info "已将MySQLdb导入替换为pymysql别名"
    else
        # 如果没有找到MySQLdb导入，则复制原文件
        cp "$INSTALL_DIR/data_spider/create_target_table.py" "$TEMP_FILE"
        log_info "未找到MySQLdb导入，跳过替换"
    fi
    
    # 修复日志配置
    log_info "修复日志配置路径..."
    sed -i '/logging.basicConfig/,/logger = logging.getLogger/c\
# 获取当前脚本路径\
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))\
PROJECT_ROOT = os.path.dirname(CURRENT_DIR)\
LOGS_DIR = os.path.join(PROJECT_ROOT, "logs")\
\
# 确保日志目录存在\
if not os.path.exists(LOGS_DIR):\
	try:\
		os.makedirs(LOGS_DIR)\
	except Exception as e:\
		print(f"无法创建日志目录: {e}")\
\
# 配置日志\
logging.basicConfig(\
	level=logging.INFO,\
	format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",\
	handlers=[\
		logging.StreamHandler(),\
		logging.FileHandler(os.path.join(LOGS_DIR, "data_processing.log"))\
	]\
)\
logger = logging.getLogger("data_processing")' "$TEMP_FILE"
    
    # 替换原始文件
    mv "$TEMP_FILE" "$INSTALL_DIR/data_spider/create_target_table.py"
    chmod 644 "$INSTALL_DIR/data_spider/create_target_table.py"
    chmod +x "$INSTALL_DIR/data_spider/create_target_table.py"
    
    log_info "已修复 data_spider/create_target_table.py 中的日志路径问题"
else
    log_warning "找不到 data_spider/create_target_table.py 文件，跳过修复"
fi

# 3. 修复web_server/main.py中的缩进问题
log_section "修复web_server/main.py"
if [ -f "$INSTALL_DIR/web_server/main.py" ]; then
    # 备份原始文件
    cp "$INSTALL_DIR/web_server/main.py" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"
    log_info "已备份原始文件到 $BACKUP_DIR/main.py.bak.$TIMESTAMP"
    
    # 修复缩进问题
    log_info "修复update_user_info方法的缩进问题..."
    # 查找问题行
    LINE_START=$(grep -n "return str(e)" "$INSTALL_DIR/web_server/main.py" | tail -1 | cut -d: -f1)
    if [ -z "$LINE_START" ]; then
        log_warning "找不到需要修复的行，尝试其他方法..."
        LINE_START=$(grep -n "def update_user_info" "$INSTALL_DIR/web_server/main.py" | cut -d: -f1)
        if [ -z "$LINE_START" ]; then
            log_error "找不到update_user_info方法，无法修复缩进问题"
        else
            LINE_START=$((LINE_START - 2))
        fi
    fi
    
    if [ -n "$LINE_START" ]; then
        log_info "找到缩进问题行: $LINE_START"
        
        # 创建临时文件
        TEMP_FILE=$(mktemp)
        
        # 处理文件的前半部分
        head -n $((LINE_START-1)) "$INSTALL_DIR/web_server/main.py" > "$TEMP_FILE"
        
        # 添加修复后的return语句和update_user_info方法
        cat >> "$TEMP_FILE" << 'EOF'
			logger.error(f"GET请求处理失败: {e}")
			return str(e)
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
        LINE_END=$(grep -n "^	def parse_cmd" "$INSTALL_DIR/web_server/main.py" | head -1 | cut -d: -f1)
        if [ -z "$LINE_END" ]; then
            log_warning "找不到parse_cmd方法，尝试其他方法..."
            LINE_END=$(grep -n "^	def " "$INSTALL_DIR/web_server/main.py" | awk -v start="$LINE_START" '$1 > start {print $1; exit}' | cut -d: -f1)
        fi
        
        if [ -n "$LINE_END" ]; then
            log_info "找到下一个方法位置: $LINE_END"
            
            # 添加文件的后半部分
            tail -n +$LINE_END "$INSTALL_DIR/web_server/main.py" >> "$TEMP_FILE"
            
            # 替换原始文件
            mv "$TEMP_FILE" "$INSTALL_DIR/web_server/main.py"
            chmod 644 "$INSTALL_DIR/web_server/main.py"
            
            log_info "已修复 update_user_info 方法的缩进问题"
        else
            log_error "找不到下一个方法，跳过修复 update_user_info 方法"
            rm "$TEMP_FILE"
        fi
    else
        log_warning "无法找到需要修复的行，跳过修复"
    fi
    
    # 检查on_event方法的缩进问题
    log_info "检查on_event方法的缩进问题..."
    if grep -q "def on_event" "$INSTALL_DIR/web_server/main.py"; then
        # 确保on_event方法的缩进正确
        sed -i 's/^	def on_event(self, recMsg):/	def on_event(self, recMsg):/' "$INSTALL_DIR/web_server/main.py"
        log_info "已检查 on_event 方法的缩进"
    fi
    
    # 修复导入，确保使用pymysql替代MySQLdb
    log_info "修复导入语句..."
    if grep -q "import MySQLdb" "$INSTALL_DIR/web_server/main.py"; then
        sed -i 's/import MySQLdb/import pymysql as MySQLdb/' "$INSTALL_DIR/web_server/main.py"
        log_info "已将MySQLdb导入替换为pymysql"
    fi
else
    log_warning "找不到 web_server/main.py 文件，跳过修复"
fi

# 4. 安装缺失的Python依赖
log_section "安装Python依赖"
log_info "安装缺失的Python依赖..."
if [ -d "$INSTALL_DIR/venv" ]; then
    "$INSTALL_DIR/venv/bin/pip" install pymysql web.py lxml
    log_info "已在虚拟环境中安装依赖"
else
    log_info "未找到虚拟环境，尝试创建新的虚拟环境..."
    python3 -m venv "$INSTALL_DIR/venv"
    "$INSTALL_DIR/venv/bin/pip" install --upgrade pip
    
    if [ -f "$INSTALL_DIR/requirements.txt" ]; then
        "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
    fi
    
    "$INSTALL_DIR/venv/bin/pip" install pymysql web.py lxml
    log_info "已创建虚拟环境并安装依赖"
    
    # 如果存在服务文件，更新Python路径
    if [ -f "/etc/systemd/system/movie-recommender.service" ]; then
        log_info "更新服务文件使用新的虚拟环境..."
        sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/web_server/main.py|" "/etc/systemd/system/movie-recommender.service"
        systemctl daemon-reload
    fi
fi

# 5. 创建MySQLdb兼容性包装
log_section "创建兼容性包装"
log_info "创建MySQLdb兼容性包装器..."
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
chmod 644 "$INSTALL_DIR/web_server/mysqldb_wrapper.py"
log_info "已创建MySQLdb兼容性包装器"

# 6. 确保导入mysqldb_wrapper
log_info "确保导入兼容性包装器..."
if [ -f "$INSTALL_DIR/web_server/main.py" ] && ! grep -q "import mysqldb_wrapper" "$INSTALL_DIR/web_server/main.py"; then
    # 在主导入后添加
    sed -i '/^import sys/a import mysqldb_wrapper' "$INSTALL_DIR/web_server/main.py"
    log_info "已添加mysqldb_wrapper导入到main.py"
fi

# 7. 修复端口绑定权限问题
log_section "修复端口绑定权限"
log_info "修复端口绑定权限问题..."
if [ -f "/etc/systemd/system/movie-recommender.service" ]; then
    # 添加端口绑定权限到服务文件
    grep -q "AmbientCapabilities=CAP_NET_BIND_SERVICE" "/etc/systemd/system/movie-recommender.service" || {
        sed -i '/\[Service\]/a AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE' "/etc/systemd/system/movie-recommender.service"
        log_info "已添加端口绑定权限到服务文件"
    }
    
    # 获取Python解释器路径
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
        apt-get update
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
    log_info "服务配置已更新"
else
    log_warning "找不到服务配置文件，跳过端口绑定权限修复"
    
    # 如果没有服务文件，创建一个新的
    log_info "创建新的服务文件..."
    PYTHON_PATH="$INSTALL_DIR/venv/bin/python"
    
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
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载systemd
    systemctl daemon-reload
    systemctl enable movie-recommender.service
    log_info "已创建并启用服务"
    
    # 设置Python解释器权限
    if [ -L "$PYTHON_PATH" ]; then
        REAL_PYTHON_PATH=$(readlink -f "$PYTHON_PATH")
        setcap 'cap_net_bind_service=+ep' "$REAL_PYTHON_PATH"
    else
        setcap 'cap_net_bind_service=+ep' "$PYTHON_PATH"
    fi
    
    if [ $? -ne 0 ]; then
        log_warning "设置权限失败，安装authbind作为备选方案..."
        apt-get update
        apt-get install -y authbind
        touch /etc/authbind/byport/80
        chmod 500 /etc/authbind/byport/80
        chown root /etc/authbind/byport/80
        
        # 修改服务文件使用authbind
        sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/authbind --deep $PYTHON_PATH $INSTALL_DIR/web_server/main.py|" "/etc/systemd/system/movie-recommender.service"
        systemctl daemon-reload
        log_info "已配置authbind作为备选方案"
    fi
fi

# 8. 重启服务
log_section "重启服务"
log_info "重启电影推荐系统服务..."
systemctl restart movie-recommender.service

# 等待服务启动
log_info "等待服务启动..."
sleep 5
if systemctl is-active --quiet movie-recommender.service; then
    log_info "服务已成功启动！"
    systemctl status movie-recommender.service --no-pager
else
    log_warning "服务可能未正确启动，检查日志："
    journalctl -u movie-recommender.service -n 30 --no-pager
    
    # 检查常见问题
    if journalctl -u movie-recommender.service -n 30 | grep -q "No module named 'web'"; then
        log_warning "检测到缺少web.py模块，尝试再次安装..."
        "$INSTALL_DIR/venv/bin/pip" install web.py
        systemctl restart movie-recommender.service
        sleep 5
        
        if systemctl is-active --quiet movie-recommender.service; then
            log_info "服务已成功启动！"
        else
            log_error "服务仍然无法启动，请检查其他可能的问题"
        fi
    elif journalctl -u movie-recommender.service -n 30 | grep -q "Permission denied"; then
        log_warning "检测到权限问题，请确保所有文件权限正确设置"
    elif journalctl -u movie-recommender.service -n 30 | grep -q "database"; then
        log_warning "检测到数据库问题，请检查数据库配置和连接"
    fi
fi

# 修复完成
log_section "修复完成"
log_info "已完成以下修复："
log_info "1. 修复了data_spider/create_target_table.py中的日志路径问题"
log_info "2. 修复了web_server/main.py中update_user_info和on_event方法的缩进错误"
log_info "3. 解决了缺少MySQLdb模块的问题，使用pymysql作为替代方案"
log_info "4. 配置了端口绑定权限，支持Python解释器符号链接情况"
log_info "5. 设置了正确的文件权限和服务配置"
log_info ""
log_info "所有原始文件已备份到: $BACKUP_DIR/"
log_info ""
log_info "如果服务仍无法正常运行，您可以检查服务日志:"
log_info "  journalctl -u movie-recommender.service -f"
log_info ""
log_info "要手动重启服务，请使用:"
log_info "  systemctl restart movie-recommender.service" 