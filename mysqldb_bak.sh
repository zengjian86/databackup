#!/bin/bash
#--------------配置参数 开始 ------------------ #
#用于docker compose
DOCKER_SERVICE_PATH=""
DOCKER_SERVICE_NAME=""
#MySql数据库文件存储目录
MYSQL_DATA_PATH=""
#bin-log索引文件
BINLOG_FILE=binlog.index
MYSQL_USER=root          #数据库管理员
MYSQL_USER_PASSWD=123456 #数据库管理员密码
#备份文件存储路径
TARGET_PATH=""
#存储binlog的目录名称
BINLOG_SAVE_PATH="binlog"
#备份日志文件
LOG_FILE=mysql_bak.log
#定义备份文件名前缀
FILE_PREFIX=mysqldb_$(date +"%Y%m%d%H%M%S")

#命令
MYSQL_DUMP_CMD="mysqldump"
MYSQL_ADMIN_CMD="mysqladmin"
#--------------配置参数 结束 ------------------ #
#========= 根据实际情况修改以上参数 ==========#
if [ ! -d $TARGET_PATH ]; then
    mkdir -p $TARGET_PATH
fi

#获取时间
get_cur_datetime() {
    echo $(date +"%Y-%m-%d %H:%M:%S")
}
#清理binlog，慎用
mysql_binlog_clear() {
    local curdir=$(pwd)
    cd $DOCKER_SERVICE_PATH
    $MYSQL_ADMIN_CMD -u${MYSQL_USER} -p${MYSQL_USER_PASSWD} refresh
    if [ $? -ne 0 ]; then
        echo $(get_cur_datetime) 清理数据库binlog 失败! >>$TARGET_PATH/$LOG_FILE
        cd $curdir
        exit 1
    fi
    cd $curdir
}
#刷新并生成新的binlog，用于增量备份
mysql_flush_logs() {
    local curdir=$(pwd)
    cd $DOCKER_SERVICE_PATH
    $MYSQL_ADMIN_CMD -u${MYSQL_USER} -p${MYSQL_USER_PASSWD} flush-logs
    if [ $? -ne 0 ]; then
        echo $(get_cur_datetime) 生成新binlog 失败! >>$TARGET_PATH/$LOG_FILE
        cd $curdir
        exit 1
    fi
    cd $curdir
}
#复制binlog
mysql_copy_binlog() {
    local binlog_path=${TARGET_PATH}/${BINLOG_SAVE_PATH}
    local counter=$(wc -l $MYSQL_DATA_PATH/$BINLOG_FILE | awk '{print $1}')
    local nextNum=0
    if [ ! -d $binlog_path ]; then
        mkdir -p $binlog_path
    fi
    for file in $(cat $MYSQL_DATA_PATH/$BINLOG_FILE); do
        base=$(basename $file)
        nextNum=$(expr $nextNum + 1)
        if [ $nextNum -ne $counter ]; then
            dest=$TARGET_PATH/$BINLOG_SAVE_PATH/$base
            if (test -e $dest); then
                echo $base 已存在不再复制!
            else
                cp $MYSQL_DATA_PATH/$base $binlog_path
                if [ $? -ne 0 ]; then
                    echo $(get_cur_datetime) 备份 $base 失败! >>$TARGET_PATH/$LOG_FILE
                    exit 1
                else
                    echo $(get_cur_datetime) 备份 $base 成功! >>$TARGET_PATH/$LOG_FILE
                fi
            fi
        fi
    done
}
#打包binlog
mysql_package_binlog() {
    local tar_file=${TARGET_PATH}/${FILE_PREFIX}.tgz
    local binlog_path=${TARGET_PATH}/${BINLOG_SAVE_PATH}
    if [ -d $binlog_path ]; then
        #如果存在增量备份，则打包增量备份并清空增量备份文件
        if [ "$(ls -A $binlog_path)" ]; then
            local curdir=$(pwd)
            cd $TARGET_PATH && tar -czf $tar_file $BINLOG_SAVE_PATH/
            if [ $? -ne 0 ]; then
                echo $(get_cur_datetime) 打包BINGLOG 失败! >>$TARGET_PATH/$LOG_FILE
                exit 1
            else
                echo $(get_cur_datetime) 打包BINGLOG 成功! >>$TARGET_PATH/$LOG_FILE
            fi
            cd $curdir
        fi
    fi
}
#到处所有数据库
mysql_dump() {
    local dump_file=${TARGET_PATH}/${FILE_PREFIX}.sql.gz
    # --delete-source-logs 清除binlog文件
    local curdir=$(pwd)
    cd $DOCKER_SERVICE_PATH
    $MYSQL_DUMP_CMD -u${MYSQL_USER} -p${MYSQL_USER_PASSWD} --quick --events --all-databases --flush-logs --flush-privileges | gzip >$dump_file
    if [ $? -ne 0 ]; then
        echo $(get_cur_datetime) 全量导出数据库 失败! >>$TARGET_PATH/$LOG_FILE
        cd $curdir
        exit 1
    else
        echo $(get_cur_datetime) 全量导出数据库 成功! >>$TARGET_PATH/$LOG_FILE
    fi
}
#打包并清除binlog
mysql_packing_clear() {
    mysql_flush_logs
    mysql_copy_binlog
    #清除binlog
    mysql_binlog_clear
    mysql_package_binlog
    #打包成功则删除
    rm -f $TARGET_PATH/$BINLOG_SAVE_PATH/*
    echo $(get_cur_datetime) 打包并清除BINGLOG 成功! >>$TARGET_PATH/$LOG_FILE
}

#全量备份
mysql_full_bak() {
    mysql_dump
    mysql_copy_binlog
}
#增量备份
mysql_incr_bak() {
    mysql_flush_logs
    mysql_copy_binlog
}

#打印提示信息
print_info() {
    echo -e " 用法:    $0  -s <mysql_data_path> -d <saved_path> -u <mysql_user> -p <mysql_passwd> [-a <docker_service_path> -n <docker_service_name>] [-f|-i|-c] \n"
    echo -e " 参数:    -u mysql用户"
    echo -e "          -p mysql密码"
    echo -e "          -s mysql数据文件目录"
    echo -e "          -d 备份文件存储目录"
    echo -e "          -a 应用路径，-n 应用服务名称，用于docker compose,如果为空，则直接调用mysql命令 "
    echo -e "          -i 增量备份"
    echo -e "          -f 全量备份"
    echo -e "          -c 打包并清理binlog"
    echo -e " 例子:  $0 -s test -d bak -uroot -p123456 -i"
}

#==================主程序开始========================#
#命令标识 0-增量，1-全量，2-打包并清理binlog
flag=10
#解析参数，选项后面的冒号表示该选项需要参数
while getopts "ifcu:p:s:d:a:n:" arg; do
    case $arg in
    i)
        flag=0
        ;;
    f)
        flag=1
        ;;
    c)
        flag=2
        ;;
    u)
        MYSQL_USER=$OPTARG
        ;;
    p)
        MYSQL_USER_PASSWD=$OPTARG
        ;;
    s)
        MYSQL_DATA_PATH=$OPTARG
        ;;
    d)
        TARGET_PATH=$OPTARG
        ;;
    a)
        DOCKER_SERVICE_PATH=$OPTARG
        ;;
    n)
        DOCKER_SERVICE_NAME=$OPTARG
        ;;
    ?) #当有不认识的选项的时候arg为?
        print_info
        exit 1
        ;;
    esac
done

if [ ! -z $DOCKER_SERVICE_PATH ] && [ ! -z $DOCKER_SERVICE_NAME ]; then
    MYSQL_DUMP_CMD="docker compose exec $DOCKER_SERVICE_NAME mysqldump"
    MYSQL_ADMIN_CMD="docker compose exec $DOCKER_SERVICE_NAME mysqladmin"
else
    if [ ! -z $DOCKER_SERVICE_PATH ] || [ ! -z $DOCKER_SERVICE_NAME ]; then
        echo -a 应用路径 -n 应用服务名称 参数错误
        print_info
        exit 1
    fi
fi

if [ -z $MYSQL_DATA_PATH ]; then
    echo -s 参数错误 >&2
    print_info
    exit 1
fi

if [ -z $TARGET_PATH ]; then
    echo -d 参数错误 >&2
    print_info
    exit 1
fi

case $flag in
0)
    mysql_incr_bak
    ;;
1)
    mysql_full_bak
    ;;
2)
    mysql_packing_clear
    ;;
*)
    print_info
    exit 1
    ;;
esac
