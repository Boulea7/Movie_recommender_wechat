#!/bin/bash
# 快速修复脚本 - 修复data_spider/create_target_table.py文件的Try-Except-Finally问题
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
log_section "电影推荐系统Try-Except-Finally问题修复脚本"
log_info "开始修复create_target_table.py文件的语法错误..."

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份原始文件
log_section "备份原始文件"
log_info "备份 data_spider/create_target_table.py 到 $BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"
cp "$INSTALL_DIR/data_spider/create_target_table.py" "$BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP"

# 将错误的MySQLdb导入改为pymysql别名
log_section "修复MySQL导入问题"
sed -i 's/import MySQLdb/import pymysql as MySQLdb/' "$INSTALL_DIR/data_spider/create_target_table.py"
log_info "已将MySQLdb导入改为pymysql别名"

# 安装缺失的依赖项
log_section "安装缺失的依赖"
if [ -d "$INSTALL_DIR/venv" ]; then
    log_info "检测到虚拟环境，在虚拟环境中安装依赖"
    "$INSTALL_DIR/venv/bin/pip" install pymysql
else
    log_info "在系统Python环境中安装依赖"
    pip install pymysql
fi

# 修复create_target_table.py文件
log_section "修复create_target_table.py文件"
cat > "$INSTALL_DIR/data_spider/create_target_table.py" << 'EOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
电影数据表创建与数据处理模块
提供对数据库表创建和数据导入功能
作者：电影推荐系统团队
日期：2023-05-20
"""

import pymysql as MySQLdb
import datetime
import os
import sys
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('../logs/data_processing.log')
    ]
)
logger = logging.getLogger('data_processing')

class DataHandle(object):
    """数据处理类，用于创建表和导入数据"""
    
    def __init__(self):
        """初始化数据处理类"""
        pass
    
    def init_connection(self, host='127.0.0.1', user='root', passwd='', db=''):
        """
        初始化数据库连接
        
        参数:
            host: 数据库主机地址，默认127.0.0.1
            user: 数据库用户名，默认root
            passwd: 数据库密码
            db: 数据库名称
            
        返回:
            MySQLdb.Connection: 数据库连接对象，或-1表示连接失败
        """
        try:
            conn = MySQLdb.connect(
                host=host,
                user=user,
                passwd=passwd,
                db=db,
                charset='utf8mb4'
            )
            logger.info(f"成功连接到数据库 {db}")
            return conn
        except Exception as e:
            logger.error(f"连接数据库失败: {str(e)}")
            return -1
    
    def close_db(self, conn):
        """
        关闭数据库连接
        
        参数:
            conn: 要关闭的数据库连接
        """
        try:
            if conn and conn != -1:
                conn.close()
                logger.info("数据库连接已关闭")
        except Exception as e:
            logger.error(f"关闭数据库连接失败: {str(e)}")
    
    def create_table(self, conn, tablename):
        """
        创建电影数据表
        
        参数:
            conn: 数据库连接
            tablename: 要创建的表名
        """
        if conn == -1:
            logger.error("无效的数据库连接")
            return
            
        cur = conn.cursor()
        
        try:
            # 检查表是否已存在
            sql_select = 'SHOW TABLES;'
            cur.execute(sql_select)
            tables = cur.fetchall()
            
            # 如果表不存在，则创建
            if (tablename,) not in tables:
                create_sql = """
                CREATE TABLE %s (
                    id INT UNSIGNED AUTO_INCREMENT,
                    title VARCHAR(100) NOT NULL,
                    score FLOAT(2),
                    num INT,
                    link VARCHAR(200) NOT NULL,
                    time DATE,
                    address VARCHAR(50),
                    other_release VARCHAR(100),
                    actors VARCHAR(1000),
                    director VARCHAR(100),
                    category VARCHAR(100),
                    PRIMARY KEY(id)
                ) DEFAULT CHARSET=utf8mb4;
                """ % tablename
                
                cur.execute(create_sql)
                logger.info(f"成功创建表 {tablename}")
            else:
                logger.info(f"表 {tablename} 已存在")
            
            conn.commit()
        except Exception as e:
            logger.error(f"创建表失败: {str(e)}")
            conn.rollback()
        finally:
            cur.close()
    
    def data_insert(self, conn, table, oldtable):
        """
        从旧表导入数据到新表
        
        参数:
            conn: 数据库连接
            table: 目标表名
            oldtable: 源表名
        """
        if conn == -1:
            logger.error("无效的数据库连接")
            return
            
        cur = conn.cursor()
        try:
            # 设置字符集
            cur.execute("SET NAMES utf8mb4")
            
            i = 0
            limit = 1
            links_seen = set()  # 用于去重
            processed_count = 0
            
            # 逐条处理数据
            while True:
                # 从源表查询数据
                query = f"SELECT * FROM {oldtable} LIMIT {i}, {limit};"
                cur.execute(query)
                row = cur.fetchall()
                i += 1
                
                # 无数据时结束循环
                if not row:
                    break
                
                # 获取电影链接并去重
                link = ''.join(row[0][3]).strip() if row[0][3] else ''
            
                if not link or link in links_seen:
                    continue
                    
                links_seen.add(link)
            
                # 处理标题
                title = ''.join(row[0][0]).strip() if row[0][0] else ''
                
                # 处理评分
                s = ''.join(row[0][1]).strip() if row[0][1] else ''
                score = float(s) if self.has_num(s) else None
            
                # 处理评分人数
                n = ''.join(row[0][2]).strip() if row[0][2] else ''
                if n:
                    # 只保留数字
                    num_str = ''.join(c for c in n if c.isdigit())
                    num = int(num_str) if num_str else None
                else:
                    num = None
                    score = None

                # 处理时间和地区信息
                other_release = None
                temp_time = ''.join(row[0][4]).strip() if row[0][4] else ''
                
                # 如果数据中含有数字，提取日期和地区
                if self.has_num(temp_time):
                    time_str = ''.join(c for c in temp_time if c.isdigit() or c == '-')
                    address = ''.join(c for c in temp_time if not (c.isdigit() or c in '()-'))
                else:
                    time_str = None
                    if '()' in temp_time:
                        address = ''.join(c for c in temp_time if c not in '()')
                    else:
                        address = None
                        other_release = temp_time
            
                # 处理演员信息
                actor_str = row[0][5] if len(row[0]) > 5 else ''
                if actor_str:
                    # 将字符串转换为列表
                    actors = actor_str.replace(']', '').replace('[', '').replace("'", "").split(",")
                    actors = [element.strip() for element in actors]
                    
                    # 提取数字信息到other_release
                    for element in list(actors):  # 使用列表副本进行迭代
                        if self.has_num(element):
                            if other_release:
                                other_release = other_release + ';' + element
                            else:
                                other_release = element
                            actors.remove(element)
            
                    actor = ','.join(actors)
                else:
                    actor = ''
                
                # 插入数据到新表
                try:
                    insert_sql = """
                    INSERT INTO {} 
                    (title, score, num, link, time, address, other_release, actors) 
                    VALUES (%s, %s, %s, %s, STR_TO_DATE(%s, '%%Y-%%m-%%d'), %s, %s, %s);
                    """.format(table)
                    
                    cur.execute(insert_sql, (
                        title, score, num, link, time_str, 
                        address, other_release, actor
                    ))
                    conn.commit()
                    processed_count += 1
                    
                    if processed_count % 100 == 0:
                        logger.info(f"已处理 {processed_count} 条记录")
                        
                except Exception as e:
                    logger.error(f"插入数据失败: {str(e)}")
                    conn.rollback()
            
            logger.info(f"数据导入完成，共处理 {processed_count} 条记录")
            
        except Exception as e:
            logger.error(f"数据处理过程中发生错误: {str(e)}")
        finally:
            if cur:
                cur.close()
                logger.info("数据库游标已关闭")
            self.close_db(conn)

    def has_num(self, s):
        """
        检查字符串是否包含数字
        
        参数:
            s: 要检查的字符串
            
        返回:
            bool: 是否包含数字
        """
        return any(char.isdigit() for char in s)

def main():
    """主函数"""
    # 创建日志目录
    log_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'logs')
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    
    # 初始化数据处理对象
    data = DataHandle()
    
    # 从配置文件或环境变量获取数据库配置
    passwd = os.environ.get("DB_PASSWORD", "MySQL_20050816Zln@233")
    db = os.environ.get("DB_NAME", "douban")
    host = os.environ.get("DB_HOST", "127.0.0.1")
    user = os.environ.get("DB_USER", "douban_user")
    
    # 连接数据库
    conn = data.init_connection(host=host, user=user, passwd=passwd, db=db)
    
    if conn != -1:
        # 设置表名
        table = "douban_movie"
        old_table = "douban_mov_bak"
        
        # 创建表
        data.create_table(conn, table)
        
        # 导入数据
        data.data_insert(conn, table, old_table)
    else:
        logger.error("无法连接到数据库，程序终止")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# 设置文件权限
chmod +x "$INSTALL_DIR/data_spider/create_target_table.py"
log_info "已设置执行权限"

# 重启服务
log_section "重启服务"
systemctl restart movie-recommender.service
log_info "服务已重启"

# 等待服务启动
log_info "等待服务启动..."
sleep 5
if systemctl is-active --quiet movie-recommender.service; then
    log_info "服务已成功启动！"
else
    log_warning "服务可能未正确启动，请检查日志：journalctl -u movie-recommender.service -f"
fi

log_section "修复完成"
log_info "create_target_table.py 文件的语法错误已修复。"
log_info "如果仍有问题，您可以恢复备份文件："
log_info "  sudo cp $BACKUP_DIR/create_target_table.py.bak.$TIMESTAMP $INSTALL_DIR/data_spider/create_target_table.py"
log_info "  sudo systemctl restart movie-recommender.service" 