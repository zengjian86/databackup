# 全量增量备份脚本
    用法:     ./data_bak.sh  -s <source_path> -d <target_path>  [-f|-i] [-w <week 1-7>]  -x <exclude_path>
    参数:    -s 备份源路径"
             -d 备份目标路径"
             -f 完全备份"
             -i 增量备份，如果未做过完全备份，则会做全量备份"
             -w 完全备份星期1-7"
             -x 排除目录名称"
    例子:  ./data_bak.sh -s test -d bak"