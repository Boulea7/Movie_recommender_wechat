#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
数据库连接管理器
提供数据库连接池和重试机制
作者：电影推荐系统团队
日期：2023-05-20
"""

import time
import pymysql
from pymysql.cursors import DictCursor
from .logger import movie_recommender_logger as logger
from .config_parser import ConfigParser

class DatabaseManager:
    """数据库连接管理器"""
    
    def __init__(self):
        """初始化数据库连接管理器"""
        # 从配置文件获取数据库配置
        config_parser = ConfigParser()
        self.db_config = config_parser.get_database_config()
        
        # 连接池
        self.connections = []
        self.max_connections = self.db_config.get('pool_size', 5)
        self.timeout = self.db_config.get('timeout', 60)
        self.reconnect_attempts = self.db_config.get('reconnect_attempts', 3)
        
        # 初始化连接池
        self._init_connection_pool()
    
    def _init_connection_pool(self):
        """初始化连接池"""
        logger.info("初始化数据库连接池")
        try:
            for _ in range(self.max_connections):
                conn = self._create_connection()
                if conn:
                    self.connections.append(conn)
        except Exception as e:
            logger.error(f"初始化连接池失败: {str(e)}")
    
    def _create_connection(self):
        """
        创建一个新的数据库连接
        
        返回:
            pymysql.Connection: 数据库连接对象
        """
        try:
            connection = pymysql.connect(
                host=self.db_config.get('host', 'localhost'),
                port=self.db_config.get('port', 3306),
                user=self.db_config.get('user', 'douban_user'),
                password=self.db_config.get('password', 'MySQL_20050816Zln@233'),
                db=self.db_config.get('db', 'douban'),
                charset=self.db_config.get('charset', 'utf8mb4'),
                connect_timeout=self.timeout,
                cursorclass=DictCursor
            )
            logger.debug("创建数据库连接成功")
            return connection
        except Exception as e:
            logger.error(f"创建数据库连接失败: {str(e)}")
            return None
    
    def _get_connection(self):
        """
        从连接池获取一个连接
        
        返回:
            pymysql.Connection: 数据库连接对象
        """
        # 检查连接池是否为空
        if not self.connections:
            logger.warning("连接池为空，创建新连接")
            return self._create_connection()
        
        # 获取连接
        connection = self.connections.pop()
        
        # 检查连接是否有效
        try:
            connection.ping(reconnect=True)
            return connection
        except Exception as e:
            logger.warning(f"连接已断开，创建新连接: {str(e)}")
            return self._create_connection()
    
    def _put_connection(self, connection):
        """
        将连接归还到连接池
        
        参数:
            connection: 要归还的数据库连接
        """
        if connection:
            # 如果连接池未满，则归还连接
            if len(self.connections) < self.max_connections:
                self.connections.append(connection)
            else:
                # 连接池已满，关闭连接
                try:
                    connection.close()
                    logger.debug("连接池已满，关闭连接")
                except Exception as e:
                    logger.warning(f"关闭连接失败: {str(e)}")
    
    def execute_query(self, sql, params=None):
        """
        执行查询SQL语句
        
        参数:
            sql: SQL查询语句
            params: 查询参数，默认为None
        
        返回:
            list: 查询结果列表
        """
        connection = None
        cursor = None
        result = []
        attempts = 0
        
        while attempts < self.reconnect_attempts:
            try:
                connection = self._get_connection()
                if not connection:
                    raise Exception("无法获取数据库连接")
                
                cursor = connection.cursor()
                cursor.execute(sql, params)
                result = cursor.fetchall()
                break  # 查询成功，跳出循环
            except Exception as e:
                attempts += 1
                if attempts >= self.reconnect_attempts:
                    logger.error(f"执行查询失败，已达最大重试次数: {str(e)}")
                    raise e  # 重试次数用完，抛出异常
                else:
                    logger.warning(f"执行查询失败，尝试重新连接 (尝试 {attempts}/{self.reconnect_attempts}): {str(e)}")
                    time.sleep(1)  # 等待1秒后重试
            finally:
                if cursor:
                    cursor.close()
                if connection:
                    self._put_connection(connection)
        
        return result
    
    def execute_update(self, sql, params=None):
        """
        执行更新SQL语句（INSERT, UPDATE, DELETE）
        
        参数:
            sql: SQL更新语句
            params: 更新参数，默认为None
        
        返回:
            int: 受影响的行数
        """
        connection = None
        cursor = None
        affected_rows = 0
        attempts = 0
        
        while attempts < self.reconnect_attempts:
            try:
                connection = self._get_connection()
                if not connection:
                    raise Exception("无法获取数据库连接")
                
                cursor = connection.cursor()
                affected_rows = cursor.execute(sql, params)
                connection.commit()
                break  # 更新成功，跳出循环
            except Exception as e:
                if connection:
                    connection.rollback()  # 发生异常时回滚事务
                
                attempts += 1
                if attempts >= self.reconnect_attempts:
                    logger.error(f"执行更新失败，已达最大重试次数: {str(e)}")
                    raise e  # 重试次数用完，抛出异常
                else:
                    logger.warning(f"执行更新失败，尝试重新连接 (尝试 {attempts}/{self.reconnect_attempts}): {str(e)}")
                    time.sleep(1)  # 等待1秒后重试
            finally:
                if cursor:
                    cursor.close()
                if connection:
                    self._put_connection(connection)
        
        return affected_rows
    
    def close_all_connections(self):
        """关闭所有连接"""
        for connection in self.connections:
            try:
                connection.close()
            except Exception as e:
                logger.warning(f"关闭连接失败: {str(e)}")
        
        self.connections = []
        logger.info("已关闭所有数据库连接")

# 全局数据库管理器实例
db_manager = DatabaseManager()

# 测试代码
if __name__ == "__main__":
    manager = DatabaseManager()
    try:
        # 测试查询
        results = manager.execute_query("SELECT * FROM douban_movie LIMIT 5")
        print(f"查询结果: {results}")
        
        # 测试插入
        affected = manager.execute_update(
            "INSERT INTO user_info (wx_id, start_time) VALUES (%s, %s)",
            ("test_user", int(time.time()))
        )
        print(f"插入影响行数: {affected}")
    except Exception as e:
        print(f"测试出错: {str(e)}")
    finally:
        # 关闭所有连接
        manager.close_all_connections() 