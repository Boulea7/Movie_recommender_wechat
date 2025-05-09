#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
配置文件解析器
用于解析数据库和系统配置
作者：电影推荐系统团队
日期：2023-05-20
"""

import os
import configparser

class ConfigParser:
    """配置文件解析器"""
    
    def __init__(self, config_path=None):
        """
        初始化配置解析器
        
        参数:
            config_path: 配置文件路径，默认为None，将使用默认路径
        """
        if config_path is None:
            # 获取当前脚本所在目录的上一级目录
            current_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            config_path = os.path.join(current_dir, 'config', 'database.conf')
        
        self.config = configparser.ConfigParser()
        
        # 尝试读取配置文件
        try:
            if os.path.exists(config_path):
                self.config.read(config_path)
            else:
                # 如果配置文件不存在，使用默认配置
                self._set_default_config()
                print(f"警告: 配置文件 {config_path} 不存在，使用默认配置")
        except Exception as e:
            # 如果读取配置文件出错，使用默认配置
            self._set_default_config()
            print(f"警告: 读取配置文件出错: {str(e)}，使用默认配置")
    
    def _set_default_config(self):
        """设置默认配置"""
        # 数据库配置
        self.config['database'] = {
            'host': 'localhost',
            'port': '3306',
            'user': 'douban_user',
            'password': 'MySQL_20050816Zln@233',
            'db': 'douban',
            'charset': 'utf8mb4',
            'pool_size': '5',
            'timeout': '60',
            'reconnect_attempts': '3'
        }
        
        # 服务配置
        self.config['service'] = {
            'port': '80',
            'token': 'HelloMovieRecommender',
            'encoding_key': 'X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a',
            'debug': 'false',
            'log_level': 'INFO'
        }
        
        # 推荐系统配置
        self.config['recommender'] = {
            'similarity_threshold': '0.5',
            'min_ratings': '3',
            'max_recommendations': '10'
        }
    
    def get_database_config(self):
        """
        获取数据库配置
        
        返回:
            dict: 数据库配置字典
        """
        try:
            db_config = {
                'host': self.config.get('database', 'host', fallback='localhost'),
                'port': self.config.getint('database', 'port', fallback=3306),
                'user': self.config.get('database', 'user', fallback='douban_user'),
                'password': self.config.get('database', 'password', fallback='MySQL_20050816Zln@233'),
                'db': self.config.get('database', 'db', fallback='douban'),
                'charset': self.config.get('database', 'charset', fallback='utf8mb4'),
                'pool_size': self.config.getint('database', 'pool_size', fallback=5),
                'timeout': self.config.getint('database', 'timeout', fallback=60),
                'reconnect_attempts': self.config.getint('database', 'reconnect_attempts', fallback=3)
            }
            return db_config
        except Exception as e:
            print(f"获取数据库配置出错: {str(e)}，将使用默认配置")
            return {
                'host': 'localhost',
                'port': 3306,
                'user': 'douban_user',
                'password': 'MySQL_20050816Zln@233',
                'db': 'douban',
                'charset': 'utf8mb4'
            }
    
    def get_service_config(self):
        """
        获取服务配置
        
        返回:
            dict: 服务配置字典
        """
        try:
            service_config = {
                'port': self.config.getint('service', 'port', fallback=80),
                'token': self.config.get('service', 'token', fallback='HelloMovieRecommender'),
                'encoding_key': self.config.get('service', 'encoding_key', fallback='X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a'),
                'debug': self.config.getboolean('service', 'debug', fallback=False),
                'log_level': self.config.get('service', 'log_level', fallback='INFO')
            }
            return service_config
        except Exception as e:
            print(f"获取服务配置出错: {str(e)}，将使用默认配置")
            return {
                'port': 80,
                'token': 'HelloMovieRecommender',
                'encoding_key': 'X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a',
                'debug': False,
                'log_level': 'INFO'
            }
    
    def get_recommender_config(self):
        """
        获取推荐系统配置
        
        返回:
            dict: 推荐系统配置字典
        """
        try:
            recommender_config = {
                'similarity_threshold': self.config.getfloat('recommender', 'similarity_threshold', fallback=0.5),
                'min_ratings': self.config.getint('recommender', 'min_ratings', fallback=3),
                'max_recommendations': self.config.getint('recommender', 'max_recommendations', fallback=10)
            }
            return recommender_config
        except Exception as e:
            print(f"获取推荐系统配置出错: {str(e)}，将使用默认配置")
            return {
                'similarity_threshold': 0.5,
                'min_ratings': 3,
                'max_recommendations': 10
            }

# 测试代码
if __name__ == "__main__":
    config_parser = ConfigParser()
    print("数据库配置:", config_parser.get_database_config())
    print("服务配置:", config_parser.get_service_config())
    print("推荐系统配置:", config_parser.get_recommender_config()) 