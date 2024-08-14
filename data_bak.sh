#!/bin/bash
BACKUP_ID="bak"             #备份唯一标识
SNAP_FILE=${BACKUP_ID}.snap #备份快照
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
WEEK=$(date +%u)
PREFIX=$(date +%Y%m%d%H%M%S)
FULL_BACK=0 #是否全量备份

#日志前缀
log_pre() {
   echo $(date +%Y:%m:%d\ %H:%M:%S)
}
#打印提示信息
print_info() {
   echo -e " 用法:    $0  -s <source_path> -d <target_path>  [-f|-i] [-w <week 1-7>]  -x <exclude_path> \n"
   echo -e " 参数:    -s 备份源路径"
   echo -e "          -d 备份目标路径"
   echo -e "          -f 完全备份"
   echo -e "          -i 增量备份，如果未做过完全备份，则会做全量备份"
   echo -e "          -w 完全备份星期1-7"
   echo -e "          -x 排除目录名称"
   echo -e " 例子:  $0 -s test -d bak"
}

#解析参数，选项后面的冒号表示该选项需要参数
while getopts "s:d:w:fix:" arg; do
   case $arg in
   s)
      SOURCE_PATH=$OPTARG
      ;;
   d)
      TARGET_PATH=$OPTARG
      ;;
   f)
      FULL_BACK=1
      ;;
   i)
      FULL_BACK=0
      ;;
   w)
      if [ "$WEEK" -eq $OPTARG ]; then
         FULL_BACK=1
      fi
      ;;
   x)
      EX_DIR=$OPTARG
      ;;
   ?) #当有不认识的选项的时候arg为?
      print_info
      exit 1
      ;;
   esac
done
if [ -z $SOURCE_PATH ]; then
   print_info
   exit 1
fi
if [ -z $TARGET_PATH ]; then
   print_info
   exit 1
fi

#判断待备份目录是否存在
if [ ! -d $SOURCE_PATH ]; then
   echo "待备份目录不存在！备份失败!" >&2
   exit 1
fi
#判断待备份目录是否存在
if [ ! -d $TARGET_PATH ]; then
   mkdir -p $TARGET_PATH
   if [ "$?" -ne "0" ]; then
      echo "不能创建目录$TARGET_PATH！备份失败!!" >&2
      exit 1
   fi
fi
#针对相对路径获取绝对路径
curdir=$(pwd)
cd $SOURCE_PATH
SOURCE_PATH=$(pwd)
cd $curdir
cd $TARGET_PATH
TARGET_PATH=$(pwd)
cd $curdir

#如果不是根目录，则取要备份的路径为备份ID
if [ ! $SOURCE_PATH = "/" ]; then
   BACKUP_ID=${SOURCE_PATH##*\/}
fi
SNAP_FILE=${BACKUP_ID}.snap
FILE_PREFIX=${BACKUP_ID}_${PREFIX}
FILE_PATH=$TARGET_PATH/$YEAR/$MONTH #按月存放备份数据

#判断目录是否存在,不存在则新建
if [ ! -d $FILE_PATH ]; then
   mkdir -p $FILE_PATH
   if [ "$?" -ne "0" ]; then
      echo "不能创建目录$FILE_PATH！备份失败!!" >&2
      exit 1
   fi
fi
#进入要备份路径的父路径,source-path返回相对路径，curdir为进入前的路径
cd_tar_parent_path() {
   #获取要备份文件夹相对路径
   TAR_PATH=${SOURCE_PATH##*\/}
   if [ -z $TAR_PATH ]; then
      echo "不能备份根路径,完全备份终止!" >&2
      exit 1
   fi
   curdir=$(pwd)
   cd $SOURCE_PATH
   cd ..
}
#全备份
full_backup() {
   tar_file=$FILE_PATH/${FILE_PREFIX}_full.tar.gz #完全备份文件名
   tar_file_snap=$FILE_PATH/${FILE_PREFIX}_full.snap #备份成功后的快照文件名
   tar_snap=$TARGET_PATH/$SNAP_FILE  #前一次备份的快照名称
   tar_snap_bak=$tar_snap.bak        #备份快照名称

   if [ -f $tar_file ]; then
      echo "$tar_file 已存在,完全备份终止!" >&2
      exit 1
   fi
   #备份快照文件已存在，则备份并移除
   if [ -f $tar_snap ]; then
      mv $tar_snap $tar_snap_bak
   fi
   cd_tar_parent_path
   tar -g $tar_snap --exclude="${EX_DIR}" -czf $tar_file ${TAR_PATH} 1>/dev/null 2>&1
   if [ $? -eq 0 ]; then
      if [ -f $tar_snap_bak ]; then
         rm $tar_snap_bak  
      fi             #成功则删除已备份快照文件
      cp -a $tar_snap $tar_file_snap #保存当前快照文件到备份目录
      echo -e "$(log_pre) 完全备份${SOURCE_PATH}成功!"
   else
      #失败处理
      mv $tar_snap_bak $tar_snap #恢复当前快照文件
      if [ -f $tar_file ]; then
         rm -r $tar_file #删除出错的备份
      fi
      echo -e "$(log_pre) 完全备份${SOURCE_PATH}失败!" >&2
   fi
   cd $curdir
}

#增量备份
incr_backup() {
   tar_file=$FILE_PATH/${FILE_PREFIX}_incr.tar.gz #完全备份文件名
   tar_file_snap=$FILE_PATH/${FILE_PREFIX}_incr.snap #备份成功后的快照文件名
   tar_snap=$TARGET_PATH/$SNAP_FILE  #前一次备份的快照名称
   tar_snap_bak=$tar_snap.bak        #备份快照名称

   if [ -f $tar_file ]; then
      echo "$tar_file 已存在,备份终止!" >&2
      exit 1
   fi
   if [ -f $tar_snap ]; then
      cp -a $tar_snap $tar_snap_bak #备份当前快照文件
      cd_tar_parent_path             #进入待备份目录的父目录，待备份目录相对路径存入变量$TAR_PATH
      tar -g $tar_snap --exclude="${EX_DIR}" -czf $tar_file $TAR_PATH 1>/dev/null 2>&1
      if [ $? -eq 0 ]; then
         mv $tar_snap_bak ${tar_file_snap}pre #保存备份前的快照
         cp -a $tar_snap $tar_file_snap #保存备份后的快照
         echo -e "$(log_pre) 增量备份${SOURCE_PATH}成功!"
      else
         mv $tar_snap_bak $tar_snap #恢复当前快照文件
         #删除出错的备份文件
         if [ -f $tar_file ]; then
            rm -f $tar_file
         fi
         echo -e "$(log_pre) 增量备份${SOURCE_PATH}失败!" >&2
      fi
      cd $curdir
   else
      full_backup
   fi
}
#开始备份
if [ $FULL_BACK -eq 1 ]; then
   full_backup
else
   incr_backup
fi
