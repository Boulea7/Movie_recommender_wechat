#!/bin/bash
# 专门修复web_server/main.py文件中的缩进问题的脚本
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
log_section "电影推荐系统 web_server/main.py 修复脚本"
log_info "开始修复web_server/main.py文件中的缩进问题..."

# 备份原始文件
mkdir -p "$BACKUP_DIR"
if [ -f "$INSTALL_DIR/web_server/main.py" ]; then
    cp "$INSTALL_DIR/web_server/main.py" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"
    log_info "已备份原始文件到 $BACKUP_DIR/main.py.bak.$TIMESTAMP"
else
    log_error "找不到 $INSTALL_DIR/web_server/main.py 文件，无法继续"
    exit 1
fi

# 创建临时文件
TEMP_FILE=$(mktemp)
log_info "创建临时文件进行修复"

# 查找问题行
LINE_START=$(grep -n "return str(e)" "$INSTALL_DIR/web_server/main.py" | tail -1 | cut -d: -f1)
if [ -z "$LINE_START" ]; then
    log_warning "找不到需要修复的行，尝试其他方法..."
    LINE_START=$(grep -n "def update_user_info" "$INSTALL_DIR/web_server/main.py" | cut -d: -f1)
    if [ -z "$LINE_START" ]; then
        log_error "找不到update_user_info方法，无法继续"
        exit 1
    else
        LINE_START=$((LINE_START - 2))
    fi
fi

log_info "找到缩进问题行: $LINE_START"

# 处理文件的前半部分
log_info "处理文件前半部分..."
head -n $((LINE_START-1)) "$INSTALL_DIR/web_server/main.py" > "$TEMP_FILE"

# 添加修复后的return语句和update_user_info方法
log_info "添加修复后的return语句和update_user_info方法..."

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
    
    if [ -z "$LINE_END" ]; then
        log_error "找不到下一个方法，无法继续"
        exit 1
    fi
fi

log_info "找到下一个方法位置: $LINE_END"

# 添加文件的后半部分
log_info "添加文件后半部分..."
tail -n +$LINE_END "$INSTALL_DIR/web_server/main.py" >> "$TEMP_FILE"

# 替换原始文件
log_info "替换原始文件..."
mv "$TEMP_FILE" "$INSTALL_DIR/web_server/main.py"
chmod 644 "$INSTALL_DIR/web_server/main.py"

# 修复on_event方法的缩进问题
log_info "检查on_event方法的缩进问题..."
if grep -q "def on_event" "$INSTALL_DIR/web_server/main.py"; then
    # 确保on_event方法的缩进正确
    sed -i 's/^	def on_event(self, recMsg):/	def on_event(self, recMsg):/' "$INSTALL_DIR/web_server/main.py"
    log_info "已检查on_event方法的缩进"
fi

# 确保所有import正确
log_info "检查pymysql导入..."
if grep -q "import MySQLdb" "$INSTALL_DIR/web_server/main.py"; then
    sed -i 's/import MySQLdb/import pymysql as MySQLdb/' "$INSTALL_DIR/web_server/main.py"
    log_info "已将MySQLdb导入替换为pymysql"
fi

# 创建MySQLdb兼容性包装
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

# 修复完成
log_section "修复完成"
log_info "web_server/main.py文件中的缩进问题已修复"
log_info "原始文件已备份到 $BACKUP_DIR/main.py.bak.$TIMESTAMP"
log_info "您现在可以重启服务: systemctl restart movie-recommender.service" 