#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
日志模块
提供应用程序的日志记录功能
作者：电影推荐系统团队
日期：2023-05-20
"""

import os
import logging
import logging.handlers
import time
from datetime import datetime

class Logger:
    """日志管理类"""
    
    def __init__(self, logger_name='movie_recommender', log_level=logging.INFO):
        """
        初始化日志系统
        
        参数:
            logger_name: 日志记录器名称
            log_level: 日志级别，默认为INFO
        """
        # 获取日志目录路径（上一级目录的logs子目录）
        current_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        log_dir = os.path.join(current_dir, 'logs')
        
        # 如果日志目录不存在，则创建
        if not os.path.exists(log_dir):
            try:
                os.makedirs(log_dir)
            except Exception as e:
                print(f"无法创建日志目录: {str(e)}")
        
        # 创建日志记录器
        self.logger = logging.getLogger(logger_name)
        self.logger.setLevel(log_level)
        
        # 避免重复添加处理器
        if not self.logger.handlers:
            # 创建日志格式
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s'
            )
            
            # 控制台处理器
            console_handler = logging.StreamHandler()
            console_handler.setFormatter(formatter)
            console_handler.setLevel(log_level)
            self.logger.addHandler(console_handler)
            
            # 文件处理器（按日期滚动）
            log_file = os.path.join(log_dir, f'{logger_name}.log')
            file_handler = logging.handlers.TimedRotatingFileHandler(
                log_file, when='midnight', interval=1, backupCount=30
            )
            file_handler.setFormatter(formatter)
            file_handler.setLevel(log_level)
            self.logger.addHandler(file_handler)
            
            # 错误日志处理器（单独记录错误和严重错误）
            error_log_file = os.path.join(log_dir, f'{logger_name}_error.log')
            error_file_handler = logging.FileHandler(error_log_file)
            error_file_handler.setFormatter(formatter)
            error_file_handler.setLevel(logging.ERROR)
            self.logger.addHandler(error_file_handler)
    
    def debug(self, message):
        """记录调试信息"""
        self.logger.debug(message)
    
    def info(self, message):
        """记录普通信息"""
        self.logger.info(message)
    
    def warning(self, message):
        """记录警告信息"""
        self.logger.warning(message)
    
    def error(self, message, exc_info=True):
        """
        记录错误信息
        
        参数:
            message: 错误信息
            exc_info: 是否记录异常堆栈信息，默认为True
        """
        self.logger.error(message, exc_info=exc_info)
    
    def critical(self, message, exc_info=True):
        """
        记录严重错误信息
        
        参数:
            message: 错误信息
            exc_info: 是否记录异常堆栈信息，默认为True
        """
        self.logger.critical(message, exc_info=exc_info)

# 全局日志实例
movie_recommender_logger = Logger()

# 测试代码
if __name__ == "__main__":
    logger = Logger()
    logger.debug("这是一条调试日志")
    logger.info("这是一条信息日志")
    logger.warning("这是一条警告日志")
    try:
        1 / 0
    except Exception as e:
        logger.error(f"发生错误: {str(e)}")
    logger.critical("这是一条严重错误日志") 