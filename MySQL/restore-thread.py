import os
import threading
import subprocess

# MySQL数据库配置
MYSQL_HOST = 'localhost'
MYSQL_PORT = 3306
MYSQL_USER = 'root'
MYSQL_PASSWORD = 'password'
MYSQL_DATABASE = 'database_name'

# 备份文件目录
BACKUP_DIR = '/path/to/backup/directory'

def restore_database(backup_file):
    # 构建恢复命令
    command = f'mysql -h {MYSQL_HOST} -P {MYSQL_PORT} -u {MYSQL_USER} -p{MYSQL_PASSWORD} {MYSQL_DATABASE} < {backup_file}'

    # 执行恢复命令
    subprocess.call(command, shell=True)

def run_restore_threads(num_threads):
    threads = []

    # 遍历备份文件目录
    for filename in os.listdir(BACKUP_DIR):
        if filename.endswith('.sql'):
            backup_file = os.path.join(BACKUP_DIR, filename)

            # 创建指定数量的线程
            for _ in range(num_threads):
                thread = threading.Thread(target=restore_database, args=(backup_file,))
                threads.append(thread)
                thread.start()

    # 等待所有线程完成
    for thread in threads:
        thread.join()

if __name__ == '__main__':
    num_threads = 5  # 指定线程数量
    run_restore_threads(num_threads)
