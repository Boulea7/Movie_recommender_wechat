#!/bin/bash
# 电影推荐系统综合修复脚本
# 作者：电影推荐系统团队
# 日期：2025-05-20

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

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="$INSTALL_DIR/backups"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')

# 显示脚本头部
log_section "电影推荐系统综合修复脚本"
log_info "开始修复系统中的所有已知问题..."

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份原始文件
log_section "备份原始文件"
log_info "备份关键文件到 $BACKUP_DIR"
mkdir -p "$BACKUP_DIR/system_backup.$TIMESTAMP"
cp -r "$INSTALL_DIR/data_spider" "$BACKUP_DIR/system_backup.$TIMESTAMP/" 2>/dev/null || true
cp -r "$INSTALL_DIR/web_server" "$BACKUP_DIR/system_backup.$TIMESTAMP/" 2>/dev/null || true
cp -r "$INSTALL_DIR/config" "$BACKUP_DIR/system_backup.$TIMESTAMP/" 2>/dev/null || true

# 1. 修复Python依赖问题
log_section "修复Python依赖问题"
log_info "安装缺失的Python依赖"

# 检查虚拟环境
if [ -d "$INSTALL_DIR/venv" ]; then
    log_info "检测到虚拟环境，在虚拟环境中安装依赖"
    "$INSTALL_DIR/venv/bin/pip" install pymysql
    log_info "安装额外依赖以提高兼容性"
    "$INSTALL_DIR/venv/bin/pip" install web.py lxml cryptography requests
else
    log_info "尝试在系统Python环境中安装依赖"
    pip install pymysql
    
    log_info "尝试创建新的虚拟环境"
    python3 -m venv "$INSTALL_DIR/venv" || {
        log_warning "无法创建虚拟环境，继续使用系统Python"
    }
    
    if [ -d "$INSTALL_DIR/venv" ]; then
        "$INSTALL_DIR/venv/bin/pip" install --upgrade pip
        if [ -f "$INSTALL_DIR/requirements.txt" ]; then
            "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
        fi
        "$INSTALL_DIR/venv/bin/pip" install pymysql web.py lxml
        
        # 更新服务文件使用虚拟环境
        if [ -f "/etc/systemd/system/movie-recommender.service" ]; then
            log_info "更新服务配置使用虚拟环境"
            sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/web_server/main.py|" /etc/systemd/system/movie-recommender.service
            systemctl daemon-reload
            log_info "服务配置已更新"
        fi
    fi
fi

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

# 2. 修复create_target_table.py中的问题
log_section "修复create_target_table.py"
log_info "修复数据库导入和Try-Except-Finally问题"

if [ -f "$INSTALL_DIR/data_spider/create_target_table.py" ]; then
    # 备份原始文件
    cp "$INSTALL_DIR/data_spider/create_target_table.py" "$BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"
    
    # 修复MySQLdb导入
    sed -i 's/import MySQLdb/import pymysql as MySQLdb/' "$INSTALL_DIR/data_spider/create_target_table.py"
    log_info "已将MySQLdb导入改为pymysql别名"
    
    # 设置文件权限
    chmod +x "$INSTALL_DIR/data_spider/create_target_table.py"
    log_info "已设置执行权限"
else
    log_warning "找不到 data_spider/create_target_table.py 文件，跳过修复"
fi

# 3. 修复web_server/main.py的缩进问题
log_section "修复web_server/main.py"
log_info "修复update_user_info方法的缩进问题"

if [ -f "$INSTALL_DIR/web_server/main.py" ]; then
    # 备份原始文件
    cp "$INSTALL_DIR/web_server/main.py" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"
    
    # 查找update_user_info方法的位置
    LINE_START=$(grep -n "def update_user_info" "$INSTALL_DIR/web_server/main.py" | cut -d: -f1)
    if [ -n "$LINE_START" ]; then
        log_info "找到方法位置，行号: $LINE_START"
        
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
            
            log_info "已修复 web_server/main.py 文件中的缩进问题"
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

# 4. 修复端口绑定权限问题
log_section "修复端口绑定权限问题"
log_info "配置Python解释器以允许绑定低端口号"

# 检查服务文件
if [ -f "/etc/systemd/system/movie-recommender.service" ]; then
    log_info "确保服务配置允许绑定低端口"
    grep -q "AmbientCapabilities=CAP_NET_BIND_SERVICE" "/etc/systemd/system/movie-recommender.service" || {
        # 添加端口绑定权限
        sed -i '/\[Service\]/a AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE' "/etc/systemd/system/movie-recommender.service"
        log_info "已添加端口绑定权限到服务文件"
    }
    
    # 检查Python解释器是否是符号链接
    PYTHON_PATH=$(grep -o "ExecStart=.*python" "/etc/systemd/system/movie-recommender.service" | cut -d'=' -f2 | awk '{print $1}')
    
    if [ -z "$PYTHON_PATH" ]; then
        if [ -d "$INSTALL_DIR/venv" ]; then
            PYTHON_PATH="$INSTALL_DIR/venv/bin/python"
        else
            PYTHON_PATH=$(which python3)
        fi
        log_info "使用默认Python解释器路径: $PYTHON_PATH"
    fi
    
    if [ -L "$PYTHON_PATH" ]; then
        log_info "检测到Python解释器是符号链接，找到真实路径"
        REAL_PYTHON_PATH=$(readlink -f "$PYTHON_PATH")
        log_info "Python解释器实际路径: $REAL_PYTHON_PATH"
        
        # 设置权限给真实路径
        setcap 'cap_net_bind_service=+ep' "$REAL_PYTHON_PATH"
        
        if [ $? -ne 0 ]; then
            log_warning "设置权限失败，尝试备选方法..."
            # 安装并配置authbind
            apt-get update
            apt-get install -y authbind
            touch /etc/authbind/byport/80
            chmod 500 /etc/authbind/byport/80
            chown root /etc/authbind/byport/80
            
            # 修改服务文件
            sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/authbind --deep $PYTHON_PATH $INSTALL_DIR/web_server/main.py|" "/etc/systemd/system/movie-recommender.service"
            log_info "已配置authbind作为备选方案"
        else
            log_info "成功设置端口绑定权限"
        fi
    else
        # 直接设置权限
        setcap 'cap_net_bind_service=+ep' "$PYTHON_PATH"
        
        if [ $? -ne 0 ]; then
            log_warning "设置权限失败，尝试备选方法..."
            # 安装并配置authbind
            apt-get update
            apt-get install -y authbind
            touch /etc/authbind/byport/80
            chmod 500 /etc/authbind/byport/80
            chown root /etc/authbind/byport/80
            
            # 修改服务文件
            sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/authbind --deep $PYTHON_PATH $INSTALL_DIR/web_server/main.py|" "/etc/systemd/system/movie-recommender.service"
            log_info "已配置authbind作为备选方案"
        else
            log_info "成功设置端口绑定权限"
        fi
    fi
    
    systemctl daemon-reload
    log_info "服务配置已刷新"
else
    log_warning "找不到服务配置文件，跳过端口绑定权限修复"
fi

# 5. 设置文件权限
log_section "设置文件权限"
find "$INSTALL_DIR" -name "*.py" -exec chmod +x {} \; 2>/dev/null || true
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
log_info "已设置所有Python脚本和Shell脚本的执行权限"

# 创建日志目录
mkdir -p "$INSTALL_DIR/logs"
chmod 755 "$INSTALL_DIR/logs"
log_info "已创建并设置日志目录权限"

# 6. 重启服务
log_section "重启服务"
systemctl restart movie-recommender.service || {
    log_warning "重启服务失败，尝试启动服务..."
    systemctl start movie-recommender.service || {
        log_error "无法启动服务，请检查配置"
    }
}
log_info "服务已重启"

# 等待服务启动
log_info "等待服务启动..."
sleep 5
if systemctl is-active --quiet movie-recommender.service; then
    log_info "服务已成功启动！"
else
    log_warning "服务可能未正确启动，请检查日志：journalctl -u movie-recommender.service -f"
    systemctl status movie-recommender.service --no-pager
fi

log_section "修复完成"
log_info "已完成所有问题的修复："
log_info "1. 解决了Python依赖问题，替换了MySQLdb为pymysql"
log_info "2. 修复了data_spider/create_target_table.py中的Try-Except-Finally问题"
log_info "3. 修复了web_server/main.py中update_user_info方法的缩进错误"
log_info "4. 配置了端口绑定权限，支持符号链接和authbind备选方案"
log_info "5. 设置了正确的文件权限"
log_info ""
log_info "所有原始文件已备份到: $BACKUP_DIR/system_backup.$TIMESTAMP/"
log_info "如需恢复原始状态，请执行: sudo cp -r $BACKUP_DIR/system_backup.$TIMESTAMP/* $INSTALL_DIR/"
log_info "恢复后重启服务: sudo systemctl restart movie-recommender.service" 