#!/bin/bash
# 专门修复data_spider/create_target_table.py文件中的日志路径问题的脚本
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
log_section "电影推荐系统 data_spider/create_target_table.py 修复脚本"
log_info "开始修复日志路径问题和MySQL导入问题..."

# 确保日志目录存在
mkdir -p "$INSTALL_DIR/logs"
chmod 755 "$INSTALL_DIR/logs"
log_info "已创建日志目录: $INSTALL_DIR/logs"

# 备份原始文件
mkdir -p "$BACKUP_DIR"
if [ -f "$INSTALL_DIR/data_spider/create_target_table.py" ]; then
    cp "$INSTALL_DIR/data_spider/create_target_table.py" "$BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"
    log_info "已备份原始文件到 $BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"
else
    log_error "找不到 $INSTALL_DIR/data_spider/create_target_table.py 文件，无法继续"
    exit 1
fi

# 创建临时文件
TEMP_FILE=$(mktemp)
log_info "创建临时文件进行修复"

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
log_info "替换原始文件..."
mv "$TEMP_FILE" "$INSTALL_DIR/data_spider/create_target_table.py"
chmod 644 "$INSTALL_DIR/data_spider/create_target_table.py"

# 安装pymysql依赖
log_info "安装pymysql依赖..."
if [ -d "$INSTALL_DIR/venv" ]; then
    "$INSTALL_DIR/venv/bin/pip" install pymysql
    log_info "已在虚拟环境中安装pymysql"
else
    pip install pymysql
    log_info "已在系统Python环境中安装pymysql"
fi

# 修复完成
log_section "修复完成"
log_info "data_spider/create_target_table.py文件中的问题已修复"
log_info "原始文件已备份到 $BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"
log_info "现在可以尝试运行数据处理脚本:"
log_info "  cd $INSTALL_DIR && python3 data_spider/create_target_table.py" 