import os
import time
import threading
import subprocess
import logging

# MySQL数据库配置
MYSQL_HOST = 'localhost'
MYSQL_PORT = 3306
MYSQL_USER = 'root'
MYSQL_PASSWORD = 'password'

# 备份目录
BACKUP_DIR = '/path/to/backup/directory'

# 分库分表信息
DATABASES = ['database1', 'database2']
TABLES = {
    'database1': ['table1', 'table2'],
    'database2': ['table3', 'table4']
}

# 日志配置
LOG_FILE = '/path/to/backup.log'
LOG_FORMAT = '%(asctime)s - %(levelname)s - %(message)s'
LOG_LEVEL = logging.INFO

def backup_table(database, table):
    # 创建备份目录
    database_dir = os.path.join(BACKUP_DIR, database)
    if not os.path.exists(database_dir):
        os.makedirs(database_dir)

    # 备份文件名
    backup_file = os.path.join(database_dir, f'{table}_{time.strftime("%Y%m%d%H%M%S")}.sql')

    # 构建备份命令
    command = f'mysqldump -h {MYSQL_HOST} -P {MYSQL_PORT} -u {MYSQL_USER} -p{MYSQL_PASSWORD} {database} {table} > {backup_file}'

    # 执行备份命令
    subprocess.call(command, shell=True)

    # 记录备份日志
    logger.info(f'Backup completed: {database}.{table}')

def backup_database(database):
    # 备份指定数据库的所有表
    for table in TABLES[database]:
        backup_table(database, table)

def run_backup_threads(num_threads):
    threads = []

    # 创建指定数量的线程
    for _ in range(num_threads):
        for database in DATABASES:
            thread = threading.Thread(target=backup_database, args=(database,))
            threads.append(thread)
            thread.start()

    # 等待所有线程完成
    for thread in threads:
        thread.join()

if __name__ == '__main__':
    # 配置日志
    logging.basicConfig(filename=LOG_FILE, format=LOG_FORMAT, level=LOG_LEVEL)
    logger = logging.getLogger()

    num_threads = 5  # 指定线程数量
    run_backup_threads(num_threads)
