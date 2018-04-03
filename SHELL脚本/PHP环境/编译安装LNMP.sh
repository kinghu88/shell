#!/bin/bash
export MYSQL=mysql-5.6.20
export NGINX=nginx-1.9.6
export LibmCrypt=libmcrypt-2.5.7
export PHP=php-5.6.11
export Paproxy_path=haproxy-1.5.4
export Llibiconv_path=libiconv-1.10
export Ngx_path=ngx_cache_purge-2.3
#--------------LAPM------------------
export Httpd_p=httpd-2.4.17
export Apr_p=apr-1.5.2
export Apr_util=apr-util-1.5.4
function showMenu(){   #选项界面
	clear
	cat <<-'EOF'
     "--------------------------------------------------------------"
     "|      Centos6 Install Helper                                |"
     "|      copyright http://www.kinghu.cc                        |"
     "--------------------------------------------------------------"
     "|      1. Installation package                               |"
     "|      2. Useradd                                            |"
     "|      3. Time set                                           |"
     "|      4. Install Nginx                                      |"
     "|      5. Install Mysql                                      |"
     "|      6. Install php                                        |"
     "|      7. Install Haproxy                                    |"
     "|      8. Install Lnmp                                       |"
     "|      9. Install Lamp                                       |"
     "|      x. Exit                                               |"
     "--------------------------------------------------------------"
EOF
	return 0
}
function selectCmd(){
	showMenu
	echo "Please select a serial number for installation [a-x]:"
	read -n 1 M
	echo
	if [ "$M" = "x" ]; then
		exit 1	
	elif [ "$M" = "1" ]; then
		echo "Installation package..."
		echo "------------------------------------"
		Environmental_package
		read -n 1 -p "Press <Enter> to continue..."
	elif [ "$M" = "2" ]; then
		echo "User add..."
		echo "------------------------------------"
		User_add
		read -n 1 -p "Press <Enter> to continue..."
	elif [ "$M" = "3" ]; then
		echo "Time set..."
		echo "------------------------------------"
		Time_set
		read -n 1 -p "Press <Enter> to continue..."
	elif [ "$M" = "4" ]; then
		echo "Install Nginx..."
		echo "------------------------------------"
		Nginx_install
		read -n 1 -p "Press <Enter> to continue..."
	elif [ "$M" = "7" ]; then
		echo "Install Haproxy..."
		echo "------------------------------------"
		HAProxy_install
		read -n 1 -p "Press <Enter> to continue..."
	elif [ "$M" = "5" ]; then
		echo "Install Mysql..."
		echo "------------------------------------"
		Mysql_install
		read -n 1 -p "Press <Enter> to continue..."
	elif [ "$M" = "6" ]; then
		echo "Install php..."
		echo "------------------------------------"
		Phpinstall
		read -n 1 -p "Press <Enter> to continue..."
	elif [ "$M" = "8" ]; then
		echo "Install Lnmp..."
		echo "------------------------------------"
		Environmental_package && Software_package && Time_set && Nginx_install && Mysql_install && Php_install && Iptables_set && Lnmp_tip
		read -n 1 -p "Press <Enter> to continue..."
	elif [ "$M" = "9" ]; then
		echo "Install Lamp..."
		echo "------------------------------------"
		LAMP_install
		read -n 1 -p "Press <Enter> to continue..."
	else
		echo "Select Error!"
		read -n 1 -p "Press <Enter> to continue..."
	fi
	selectCmd
	return 0
}
function Environmental_package(){   #基础依赖包安装
    Software_package
    printf "%1s \033[1;32m Environmental_package Starting...\033[0m \n"
    #yum -y install lrzsz
    yum -y install gcc make cmake curl-devel bzip2 bzip2-devel libtool glibc
    #yum -y install pcre pcre-devel openssl openssl-devel gd gd-devel perl perl-ExtUtils-Embed
}
function Software_package()
{   #删除系统自带的lnmp环境

    if rpm -qa |grep mysql
    then
        yum -y remove mysql*
    else
        printf "%1s \033[1;32m ......Mysql not installed\033[0m \n"
    fi
    if rpm -qa |grep php
    then
        yum -y remove php*
    else
        printf "%1s \033[1;32m ......PHP not installed\033[0m \n"
    fi
    if rpm -qa |grep httpd
    then
        yum -y remove httpd
    else
        printf "%1s \033[1;32m ......Httpd not installed\033[0m \n"
    fi
}
function Time_set()
{   #设置时间同步
   yum -y install ntp
    service ntpd start
    chkconfig --level 35 ntpd on
    rm -f /etc/localtime
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    cat <<-'EOF' > /etc/sysconfig/clock 
    ZONE="Asia/Shanghai"
    UTC=false
    ARC=false
    EOF

    cat <<-'EOF' > /etc/ntp.conf 
    server 128.138.140.44 prefer
    server 132.163.4.102
    server ntp.fudan.edu.cn
    server time-a.nist.gov
    server asia.pool.ntp.org
    driftfile /var/db/ntp.drift
EOF

    ntpdate asia.pool.ntp.org >/dev/null 2>&1
    /sbin/hwclock --systohc
    echo '*/30 * * * *  root ntpdate asia.pool.ntp.org >/dev/null 2>&1' >> /etc/crontab
    service crond restart
    echo "时间同步成功！"
}
function User_add()
{   #添加用户和组
read  -p "请输入username:" user1
read  -p "请输入groupname:" group1
groupadd $group1
useradd -r -s /sbin/nologin -g $group1 $user1 
}
function HAProxy_install()
{   #Haproxy 安装
groupadd -g 1004 haproxy
useradd -r -s /sbin/nologin -u 1004 -g haproxy haproxy 
yum -y install gcc    
cd /app               
if [ -e /app/$Paproxy_path.tar.gz ]
then
printf "%1s \033[1;32m Find Haproxy pakage！！ \033[0m \n"
else
printf "%1s \033[1;32m Don't find Haproxy pakage！！ \033[0m \n"
exit 1
fi
tar -zxvf $Paproxy_path.tar.gz  -C  /usr/src/    
cd /usr/src/$Paproxy_path
Kernel_ver=$(/bin/uname -r)
Kernel_HA=${Kernel_ver:0:1}${Kernel_ver:2:1}${Kernel_ver:4:1}${Kernel_ver:5:1}
make TARGET=linux$Kernel_HA
make install
cd /
mkdir  /var/haproxy
cat >> /etc/security/limits.conf  <<EOF
*            soft             nofile        65535
*            hard           nofile        65535
EOF
cat >> /etc/rsyslog.conf  <<EOF
$ModLoad       imudp
$UDPServerRun     514
local3.*      /var/log/haproxy.log 
EOF
service rsyslog restart          
touch /etc/haproxy.cfg
cat > /etc/haproxy.cfg  <<EOF
global     
    log 127.0.0.1 local3  info    
    maxconn 4096			 
    chroot /var/haproxy		
    uid 1004 				
    gid 1004
    daemon					 
    quiet				
    nbproc 1				 
    pidfile /var/run/haproxy.pid 
	ulimit-n 65535 			 
defaults   
    log global
    mode http				 
    maxconn 20480			 
    option httplog			 
    option httpclose		 
    option forwardfor        
    option dontlognull		 
    option redispatch		
	stats refresh 30
    retries 3				 
    balance roundrobin		 
    timeout connect 5000ms  
    timeout client  50000ms  
    timeout server  50000ms	 
	timeout check   2000ms   
listen web_poll  
	bind 192.168.88.8:80
    mode http				 
	log global
    option httplog
    option dontlognull
    #option logasap
    option forwardfor
    option httpclose
    option httpchk GET /index.html 
	server web1 192.168.88.101:80 cookie web1 check inter 2000 rise 2 fall 3 weight 1
	server web2 192.168.88.102:80 cookie web2 check inter 2000 rise 2 fall 3 weight 1
listen admin_status  
	bind 10.10.10.128:8080
	mode http
	log 127.0.0.1 local3  info 
    stats enable
	stats refresh 5 			 
    stats uri /stats			 
    stats auth admin:123456		 
    stats realm  Haproxy\ statistic
	stats hide-version 			 
EOF
haproxy   -f   /etc/haproxy.cfg
if [ $? != 0 ]
then
printf "%1s \033[1;32m There is something wrong with the configuration！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Successful！！ \033[0m \n"
fi
echo    "/usr/local/sbin/haproxy    -f    /etc/haproxy.cfg"    >>     /etc/rc.loacl
}
function Nginx_install()
{   #Nginx 安装
for i in `seq -w 5 -1 1`
   do
     echo -ne "+";
     sleep 1;
   done
echo
printf "%1s \033[1;32m nginx start installing... \033[0m \n"
groupadd www
useradd -r -s /sbin/nologin -g www www
yum -y install pcre pcre-devel openssl openssl-devel gd gd-devel perl perl-ExtUtils-Embed
cd /app
tar -xzf $Ngx_path.tar.gz -C /usr/local/
#wget http://nginx.org/download/${NGINX}.tar.gz  
tar -xzf ${NGINX}.tar.gz -C /usr/src/
cd /usr/src/${NGINX}/
#./configure --prefix=/usr/local/nginx  --user=www --group=www --with-http_gzip_static_module --with-http_stub_status_module --with-google_perftools_module --with-http_ssl_module --with-http_realip_module --with-http_addition_module --with-http_dav_module --with-http_perl_module    
./configure --prefix=/usr/local/nginx --add-module=/usr/local/$Ngx_path --user=www --group=www --with-http_gzip_static_module --with-http_stub_status_module  --with-http_ssl_module --with-http_realip_module --with-http_addition_module --with-http_dav_module --with-http_perl_module --with-http_flv_module
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m Nginx installation failed！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m nginx installation successful ！！ \033[0m \n"
fi
chown -R www.www /usr/local/nginx
mkdir /tmp/tcmalloc
chmod 0777 /tmp/tcmalloc
mv /usr/local/nginx/conf/nginx.conf /usr/local/nginx/conf/nginx.conf.bak
cat > /usr/local/nginx/conf/nginx.conf <<-"EOF"
user  www www; 
worker_processes  2; 
worker_rlimit_nofile 65535;  
error_log  logs/error.log  notice;
pid        logs/nginx.pid;
events {
    use epoll; 
    worker_connections  1024;  
	multi_accept on;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    access_log  logs/access.log  main;
    sendfile        on;
    tcp_nopush     on;
    tcp_nodelay   on;
    keepalive_timeout  60;
    client_header_timeout 10;
    client_body_timeout 10;
    send_timeout 20;
    client_max_body_size 30m;
############################################
    gzip on;
    gzip_min_length 1k;
    gzip_buffers 8 64k;
    gzip_http_version 1.1;
    gzip_comp_level 4;
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/x-httpd-php
    gzip_vary on;
#############################################    
    server {
        listen       80;
        server_name  localhost;
        charset utf-8;
        access_log  logs/localhost.access.log  main;
        location / {
            root   html;
            index  index.php  index.html index.htm;
        }

        error_page  404              /404.html;
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
        location ~ \.php$ {
            #root           html;
            fastcgi_pass   127.0.0.1:9000;
            fastcgi_index  index.php;
	    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include        fastcgi_params;
        }
    }
}
EOF
chown www.www /usr/local/nginx/conf/nginx.conf
echo "/usr/local/nginx/sbin/nginx" >> /etc/rc.d/rc.local
rm -rf /usr/local/nginx/html/index.html
echo "<?php phpinfo();?>" > /usr/local/nginx/html/index.php
}
function Mysql_install()
{   #Mysql 安装
for i in `seq -w 5 -1 1`
   do
     echo -ne "!";
     sleep 1;
   done
echo
printf "%1s \033[1;32m Mysql start installing... \033[0m \n"
yum -y install  ncurses-devel libxml2-devel libxml2 libtool-ltdl-devel gcc-c++ autoconf automake bison zlib-devel
cd /app
#wget http://dev.mysql.com/get/Wownload/MySQL-.6/$MYSQL.tar.gz
groupadd mysql
useradd -r -s /sbin/nologin -g mysql mysql
tar -xzf ${MYSQL}.tar.gz -C /usr/src/
cd /usr/src/${MYSQL}/
cmake . -DENABLE_DOWNLOADS=1
make && make install
printf "%1s \033[1;32m Mysql basic installation is complete! \033[0m \n"
chown -R mysql.mysql /usr/local/mysql
/usr/local/mysql/scripts/mysql_install_db --user=mysql --basedir=/usr/local/mysql/ --datadir=/usr/local/mysql/data
cp -r /usr/local/mysql/my.cnf  /etc/my.cnf
printf "%1s \033[1;32m my.cnf copy complete! \033[0m \n"
cp -r /usr/local/mysql/support-files/mysql.server  /etc/init.d/mysqld
chkconfig --add mysqld
chkconfig mysqld on
printf "%1s \033[1;32m Chkconfig mysqld on is OK!! \033[0m \n"
service mysqld start
PATH=$PATH:/usr/local/mysql/bin/
echo "export PATH=$PATH:/usr/local/mysql/bin/"  >> /etc/profile
mysqladmin -u root password "123456"
if [ $? != 0 ]
then
printf "%1s \033[1;32m Mysql is complete！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Mysql problems！！ \033[0m \n"
fi
}

function Php_install()
{   #Php 安装

#################################一、libmcrypt package#################################
printf "%1s \033[1;32m libmcrypt安装... \033[0m \n"
#wget ftp://mcrypt.hellug.gr/pub/crypto/mcrypt/libmcrypt/${LibmCrypt}.tar.gz
cd /app && tar -zxvf ${LibmCrypt}.tar.gz -C /usr/src/ && cd /usr/src/${LibmCrypt}
./configure --prefix=/usr/local/ && make -j 4 && make install
if [ $? != 0 ]
then
    printf "%1s \033[1;32m Libmcrypt安装失败！！ \033[0m \n"
    exit 1
else
    printf "%1s \033[1;32m Libmcrypt安装成功！！ \033[0m \n"
    echo "/usr/local/lib" >> /etc/ld.so.conf && /sbin/ldconfig
fi
#################################libmcrypt package#################################

#################################二、Llibiconv package#################################
printf "%1s \033[1;32m Llibiconv安装... \033[0m \n"
cd /app && tar zxf ${Llibiconv_path}.tar.gz -C /usr/src/ && cd /usr/src/${Llibiconv_path}
./configure --prefix=/usr/local/libiconv
if [ $? != 0 ]
then
    printf "%1s \033[1;32m libiconv 编译失败！ \033[0m \n"
    exit 1
else
    printf "%1s \033[1;32m libiconv 编译成功！！ \033[0m \n"
    make -j 4 && make install
fi
#################################Llibiconv package#################################

#################################三、PHP7 package#################################
printf "%1s \033[1;32m PHP7安装开始... \033[0m \n"
yum install -y gmp-devel libmcrypt-devel libxslt-devel \
openssl-devel zlib-devel libxml2-devel \
libjpeg-devel  freetype-devel libpng-devel \
gd-devel libcurl-devel 

cd /app && tar -xzf ${PHP}.tar.gz -C /usr/src/ && cd /usr/src/${PHP}
./configure --prefix=/usr/local/php --with-iconv-dir=/usr/local/libiconv \
--with-jpeg-dir --with-png-dir --with-freetype-dir  \
--with-zlib  --with-libxml-dir --with-mcrypt --with-gd \
--with-curl --with-gmp --with-gettext --with-mhash \
--with-openssl  --with-xmlrpc --with-pear  --enable-bcmath \
--enable-gd-native-ttf --enable-xml --enable-fpm  \
--enable-embedded-mysqli --enable-mbstring \
--enable-inline-optimization --enable-sockets \
--enable-zip --enable-sysvmsg --enable-sysvsem \
--enable-sysvshm --enable-soap --enable-ftp \
--disable-debug --disable-ipv6 \
--with-mysql --with-mysqli
if [ $? != 0 ]
then
    printf "%1s \033[1;32m PHP编译失败！！ \033[0m \n"
    exit 1
else
    printf "%1s \033[1;32m PHP编译成功！！ \033[0m \n"
    make -j 4 && make install
fi

cd /usr/src/${PHP} && cp -r php.ini-development /usr/local/php/lib/php.ini && chown -R www.www /usr/local/php
cp -r /usr/local/php/etc/php-fpm.conf.default /usr/local/php/etc/php-fpm.conf 
#set 【;listen.owner = nobody】【;listen.group = nobody】为 【listen.owner = www】【listen.group = www】
sed -i '/user = nobody/c user = www' /usr/local/php/etc/php-fpm.conf
sed -i '/group = nobody/c group = www' /usr/local/php/etc/php-fpm.conf
sed -i '/;listen.group = nobody/a listen.group = www\nlisten.owner = www' /usr/local/php/etc/php-fpm.conf
#set 【;date.timezone =】 to 【date.timezone = Asia/Shanghai  or  PRC 】
sed -i '/;date.timezone =/a date.timezone = Asia/Shanghai' /usr/local/php/lib/php.ini
#------------------------------------------------------------------------
echo "/usr/local/php/sbin/php-fpm" >> /etc/rc.d/rc.local
#################################PHP7 package#################################
}


function phpinstall()
{   #Php 安装  编译不含mysql
 for i in `seq -w 5 -1 1`
   do
     echo -ne "!";
     sleep 1;
   done
 echo
printf "%1s \033[1;32m PHP 安装开始... \033[0m \n"
#-----------------------------libmcrypt package-----------------------
cd /app
#wget ftp://mcrypt.hellug.gr/pub/crypto/mcrypt/libmcrypt/${LibmCrypt}.tar.gz
tar -zxvf ${LibmCrypt}.tar.gz -C /usr/src/
cd /usr/src/${LibmCrypt}
./configure --prefix=/usr/local/
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m Libmcrypt is complete！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Libmcrypt problems！！ \033[0m \n"
fi
#-----------------------------libmcrypt package-----------------------
for i in `seq -w 5 -1 1`
   do
     echo -ne "!";
     sleep 1;
   done
 echo
echo "/usr/local/lib" >> /etc/ld.so.conf
/sbin/ldconfig
if [ $? != 0 ]
then
printf "%1s \033[1;32m /usr/local/lib Write failed！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m /usr/local/lib Write to successful！！ \033[0m \n"
fi

printf "%1s \033[1;32m Php starting... \033[0m \n"
yum install -y gmp-devel libmcrypt-devel libxslt-devel openssl-devel zlib-devel libxml2-devel libjpeg-turbo-devel libiconv-devel freetype-devel libpng-devel gd-devel libcurl-devel
cd /app
#wget http://cn2.php.net/distributions/${PHP}.tar.gz
tar zxf $Llibiconv_path.tar.gz -C /usr/src/
cd /usr/src/$Llibiconv_path
./configure --prefix=/usr/local/libiconv
if [ $? != 0 ]
then
printf "%1s \033[1;32m /usr/local/libiconv Write failed！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m /usr/local/libiconv Write to successful！！ \033[0m \n"
fi
make && make install
cd /app
tar -xzf ${PHP}.tar.gz -C /usr/src/
cd /usr/src/${PHP}
./configure --prefix=/usr/local/php --with-jpeg-dir=/usr/lib64 --with-png-dir=/usr/lib64 --with-freetype-dir  --with-zlib  --with-libxml-dir --with-mcrypt --with-gd --with-curl --with-gmp --with-gettext --with-mhash --with-openssl --with-iconv-dir=/usr/local/libiconv --with-xmlrpc --with-pear --with-zend-vm=CALL --enable-zend-multibyte --enable-bcmath --enable-gd-native-ttf --enable-xml --enable-fpm  --enable-embedded-mysqli --enable-mbstring --enable-inline-optimization --enable-sockets --enable-zip --enable-sysvmsg --enable-sysvsem --enable-sysvshm --enable-soap --enable-ftp --disable-debug --disable-ipv6 --with-mysql --with-mysqli
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m PHP installation failed！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m PHP installation successful！！ \033[0m \n"
fi
cd /usr/src/${PHP}
cp -r php.ini-development /usr/local/php/lib/php.ini
chown -R www.www /usr/local/php
cp -r /usr/local/php/etc/php-fpm.conf.default /usr/local/php/etc/php-fpm.conf 
#set 【;listen.owner = nobody】【;listen.group = nobody】为 【listen.owner = www】【listen.group = www】
sed -i '/user = nobody/c user = www' /usr/local/php/etc/php-fpm.conf
sed -i '/group = nobody/c group = www' /usr/local/php/etc/php-fpm.conf
sed -i '/;listen.group = nobody/a listen.group = www\nlisten.owner = www' /usr/local/php/etc/php-fpm.conf
#------------------------------------------------------------------------
#set 【;date.timezone =】 to 【date.timezone = Asia/Shanghai  or  PRC 】
sed -i '/;date.timezone =/a date.timezone = Asia/Shanghai' /usr/local/php/lib/php.ini
#------------------------------------------------------------------------
echo "/usr/local/php/sbin/php-fpm" >> /etc/rc.d/rc.local
}
function Lnmp_tip()
{   #LNMP安装小提示
printf "%1s \033[1;32m mysql密码：123456！！ \033[0m \n"
/usr/local/nginx/sbin/nginx
/usr/local/php/sbin/php-fpm
PATH=$PATH:/usr/local/mysql/bin/
echo "export PATH=$PATH:/usr/local/mysql/bin/"  >> /etc/profile
}
function Iptables_set()
{  #设置防火墙
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 3306 -j ACCEPT
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
service iptables save
service iptables restart 
printf "%1s \033[1;32m iptables is successful！！ \033[0m \n"
}
function LAMP_install()
{   #LAMP安装
yum -y install gcc make cmake ncurses-devel libxml2-devel libxml libtool-ltdl-devel gcc-c++ autoconf automake bison zlib-devel pcre pcre-devel openssl openssl-devel gd gd-devel perl perl-ExtUtils-Embed curl-devel bzip2 bzip2-devel
echo "Environmental installation is complete"

echo "******************mysql install start******************"
cd /app
groupadd mysql
useradd -r -s /sbin/nologin -g mysql mysql
echo "Account set up successful!"
tar -xzf $MYSQL.tar.gz -C /usr/src/
cd /usr/src/$MYSQL/
echo "Unpack the success!"
cmake . -DENABLE_DOWNLOADS=1
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m Mysql编译失败! \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Mysql编译成功! \033[0m \n"
fi
chown -R mysql.mysql /usr/local/mysql
/usr/local/mysql/scripts/mysql_install_db --user=mysql --basedir=/usr/local/mysql/ --datadir=/usr/local/mysql/data
cp -r /usr/local/mysql/my.cnf /etc/my.cnf
echo "my.cnf cp complete!"
cp -r /usr/local/mysql/support-files/mysql.server /etc/init.d/mysqld
chkconfig --add mysqld
chkconfig mysqld on
echo "Chkconfig mysqld on complete!!!"
PATH=$PATH:/usr/local/mysql/bin/
echo "It's OK!!!"
echo "export PATH=$PATH:/usr/local/mysql/bin/"  >> /etc/profile
echo "It's Complete!!!"

echo "******************Apache install start******************"
cd /app
tar -xzf $Httpd_p.tar.gz -C /usr/src/
tar -xzf $Apr_p.tar.gz -C /usr/src/
tar -xzf $Apr_util.tar.gz -C /usr/src/
cd /usr/src/$Apr_p
./configure
if [ $? != 0 ]
then
printf "%1s \033[1;32m Apr编译失败! \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Apr编译成功!  \033[0m \n"
fi
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m Apr安装失败! \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Apr安装成功!  \033[0m \n"
fi
cd /usr/src/$Apr_util/
./configure --with-apr=/usr/local/apr/
if [ $? != 0 ]
then
printf "%1s \033[1;32m apr-util编译失败! \033[0m \n"
exit 1
else
printf "%1s \033[1;32m apr-util编译成功!  \033[0m \n"
fi
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m apr-util安装失败! \033[0m \n"
exit 1
else
printf "%1s \033[1;32m apr-util安装成功!  \033[0m \n"
fi
cd /usr/src/$Httpd_p/
./configure --prefix=/usr/local/apache2 --enable-so --enable-ssl --enable-rewrite --with-mpm=worker --with-suexec-bin --with-apr=/usr/local/apr/
if [ $? != 0 ]
then
printf "%1s \033[1;32m Hpttd编译失败! \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Hpttd编译成功!  \033[0m \n"
fi
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m Hpttd安装失败! \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Hpttd安装成功!  \033[0m \n"
fi
echo "It's Complete!!!"
/usr/local/apache2/bin/apachectl start

echo "******************PHP install start******************"
printf "%1s \033[1;32m PHP 安装开始... \033[0m \n"
#-----------------------------libmcrypt package-----------------------
cd /app
#wget ftp://mcrypt.hellug.gr/pub/crypto/mcrypt/libmcrypt/${LibmCrypt}.tar.gz
tar -zxvf ${LibmCrypt}.tar.gz -C /usr/src/
cd /usr/src/${LibmCrypt}
./configure --prefix=/usr/local
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m Libmcrypt is complete！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m Libmcrypt problems！！ \033[0m \n"
fi
#-----------------------------libmcrypt package-----------------------
for i in `seq -w 5 -1 1`
   do
     echo -ne "!";
     sleep 1;
   done
 echo
echo "/usr/local/lib" >> /etc/ld.so.conf
/sbin/ldconfig
if [ $? != 0 ]
then
printf "%1s \033[1;32m /usr/local/lib Write failed！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m /usr/local/lib Write to successful！！ \033[0m \n"
fi

printf "%1s \033[1;32m Php starting... \033[0m \n"
yum install -y gmp-devel libmcrypt-devel libxslt-devel openssl-devel zlib-devel libxml2-devel libjpeg-turbo-devel libiconv-devel freetype-devel libpng-devel gd-devel libcurl-devel
cd /app
#wget http://cn2.php.net/distributions/${PHP}.tar.gz
tar zxf $Llibiconv_path.tar.gz -C /usr/src/
cd /usr/src/$Llibiconv_path
./configure --prefix=/usr/local/libiconv
if [ $? != 0 ]
then
printf "%1s \033[1;32m /usr/local/libiconv Write failed！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m /usr/local/libiconv Write to successful！！ \033[0m \n"
fi
make && make install
cd /app
tar -xzf ${PHP}.tar.gz -C /usr/src/
cd /usr/src/${PHP}
#./configure --prefix=/usr/local/php5 --with-mysql=/usr/local/mysql/ --with-apxs2=/usr/local/apache2/bin/apxs --enable-mbstring --enable-sockets
./configure --prefix=/usr/local/php5  --with-jpeg-dir=/usr/lib64 --with-png-dir=/usr/lib64 --with-freetype-dir  --with-zlib  --with-libxml-dir --with-mcrypt --with-gd --with-curl --with-gmp --with-gettext --with-mhash --with-openssl --with-iconv-dir=/usr/local/libiconv --with-xmlrpc --with-pear --with-zend-vm=CALL --enable-zend-multibyte --enable-bcmath --enable-gd-native-ttf --enable-xml --enable-fpm  --enable-embedded-mysqli --enable-mbstring --enable-inline-optimization --enable-sockets --enable-zip --enable-sysvmsg --enable-sysvsem --enable-sysvshm --enable-soap --enable-ftp --disable-debug --disable-ipv6 --with-mysql=/usr/local/mysql/ --with-apxs2=/usr/local/apache2/bin/apxs
make && make install
if [ $? != 0 ]
then
printf "%1s \033[1;32m PHP installation failed！！ \033[0m \n"
exit 1
else
printf "%1s \033[1;32m PHP installation successful！！ \033[0m \n"
fi
cd /usr/src/${PHP}
cp -r php.ini-development /usr/local/php5/lib/php.ini
chown -R www.www /usr/local/php5
cp -r /usr/local/php5/etc/php-fpm.conf.default /usr/local/php5/etc/php-fpm.conf 
#set 【;listen.owner = nobody】【;listen.group = nobody】为 【listen.owner = www】【listen.group = www】
sed -i '/user = nobody/c user = www' /usr/local/php5/etc/php-fpm.conf
sed -i '/group = nobody/c group = www' /usr/local/php5/etc/php-fpm.conf
sed -i '/;listen.group = nobody/a listen.group = www\nlisten.owner = www' /usr/local/php5/etc/php-fpm.conf
#------------------------------------------------------------------------
#set 【;date.timezone =】 to 【date.timezone = Asia/Shanghai  or  PRC 】
sed -i '/;date.timezone =/a date.timezone = Asia/Shanghai' /usr/local/php5/lib/php.ini
#------------------------------------------------------------------------
echo "/usr/local/php5/sbin/php-fpm" >> /etc/rc.d/rc.local

echo "******************iptables******************"
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 3306 -j ACCEPT
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
service iptables save
service iptables restart
echo "Iptables is complete"
printf "%100s \033[1;32m 修改apache配置文件，httpd.conf！！ \033[0m \n"
printf "%100s \033[1;32m 在httpd.conf中找到 AddType段，添加 AddType application/x-httpd-php .php \033[0m \n"
printf "%100s \033[1;32m 在httpd.conf中确保有:LoadModule php5_module modules/libphp5.so \033[0m \n"
}
selectCmd
