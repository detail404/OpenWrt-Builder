#!/bin/bash
function color_echo {
    local prefixstr="$1"
    case ${prefixstr,,} in
      red)
        prefixstr='\033[31m'
        ;;
      green)
        prefixstr='\033[32m'
        ;;
      yellow)
        prefixstr='\033[33m'
        ;;
      boldred)
        prefixstr='\033[1;31m'
        ;;
      boldgreen)
        prefixstr='\033[1;32m'
        ;;
      boldyellow)
        prefixstr='\033[1;33m'
        ;;
    esac
    echo -e "${prefixstr}$2\033[00m"
}

function type_image {
    if ls "$1"*.img >/dev/null 2>&1 ; then
        IMAGE_GZ="N"
        IMAGE_NAME=$(ls "$1"*.img | head -n 1)
        color_echo green "检测到IMG文件 ${IMAGE_NAME}"
    elif ls "$1"*.img.gz >/dev/null 2>&1 ; then
        IMAGE_GZ="Y"
        IMAGE_NAME=$(ls "$1"*.img.gz | head -n 1)
        color_echo green "检测到GZ文件 ${IMAGE_NAME}"
    else
        color_echo BOLDred '没有找到受支持的刷机包'
        exit 132
    fi
}

function check_hash {
    local hashtype="$1"
    if grep "${IMAGE_NAME}$" "${hashtype}"_*.hash >"${hashtype}hash.txt" 2>/dev/null ; then
        if "${hashtype}sum" -c "${hashtype}hash.txt" ; then
            color_echo green "${hashtype^^}校验通过"
            rm -f "${hashtype}hash.txt"
        else
            color_echo BOLDred "${hashtype^^}校验失败"
            rm -f "${hashtype}hash.txt"
            case ${hashtype} in
              sha256)
                exit 129
                ;;
              md5)
                exit 130
                ;;
              *)
                exit 133
                ;;
            esac
        fi
    else
        color_echo yellow "跳过${hashtype^^}校验"
    fi
}

function copy_so_file_to_pwd {
    local linkname=$(basename "$1")
    if [ ! -f "${linkname}" ] ; then    
        if [ -L "$1" ] ; then
            local sofile=$(readlink -f "$1")
            local soname=$(basename "${sofile}")
            cp -f "${sofile}" ./
            ln -s "${soname}" "${linkname}"
        elif [ -f "$1" ] ; then
            cp -f "$1" ./
        else
            color_echo BOLDred "无法找到文件$1"
            exit 136
        fi
    fi
}

cd /tmp || exit 135
[ -d 'uploads' ] || mkdir uploads && cd uploads || exit 134

type_image openwrt

color_echo BOLDred '您确认要开始刷机吗？'
color_echo red '此操作将清空您的MicroSD卡上的数据。'
mytimeout=20
color_echo red "如果您打算放弃操作，请在${mytimeout}秒内按下Ctrl+C组合键。"
for i in $(seq ${mytimeout} -1 1) ; do
    echo -ne "\r\t\033[31m${i}秒\033[00m后将开始刷机...\t"
    sleep 1
done
echo -ne "\r\t\033[31m0秒\033[00m后将开始刷机...\t"
echo -ne "\r                                    \n"
color_echo green '已启动刷机流程...\n请不要操作键盘等输入设备，并保持电源接通。'

cp -f "$(which busybox)" ./
cp -f "$(which bash)" ./
if type shred >/dev/null 2>&1 ; then
    cp -f "$(which shred)" ./
fi

[ -d 'lib' ] || mkdir lib && cd lib || exit 134
for i in $(ldd "$(which busybox)" | awk 'NF == 4 {print $3}; NF == 2 {print $1}') ; do
    copy_so_file_to_pwd "${i}"
done
for i in $(ldd "$(which bash)" | awk 'NF == 4 {print $3}; NF == 2 {print $1}') ; do
    copy_so_file_to_pwd "${i}"
done
if type shred >/dev/null 2>&1 ; then
    for i in $(ldd "$(which shred)" | awk 'NF == 4 {print $3}; NF == 2 {print $1}') ; do
        copy_so_file_to_pwd "${i}"
    done
fi
export LD_LIBRARY_PATH="$(pwd)"
cd .. || exit 134

check_hash sha256
check_hash md5
if [ "${IMAGE_GZ}" == 'N' ] ; then
    mv "${IMAGE_NAME}" firmware.img
elif [ "${IMAGE_GZ}" == 'Y' ] ; then
    if gzip -t "${IMAGE_NAME}" ; then
        color_echo green '压缩包测试通过'
    else
        color_echo red '压缩包可能已经损坏'
        exit 131
    fi
    mv "${IMAGE_NAME}" firmware.img.gz
else
    color_echo BOLDred 'unreachable'
    exit 134
fi
echo 1 > /proc/sys/kernel/sysrq
echo u > /proc/sysrq-trigger
if [ -n "$CLEANDISK" ] ; then
    color_echo green '开始擦除MicroSD卡：通常这将消耗很长时间。'
    if [[ $CLEANDISK =~ ^[1-9][0-9]*$ ]] ; then
        DDARGU=$((256 * $CLEANDISK))
        ./busybox dd conv=fsync bs=8M count=$DDARGU if=/dev/zero of=/dev/mmcblk0
    else
        if [ -f "shred" ] ; then
            ./shred -n 0 -z -v /dev/mmcblk0
        else
            ./busybox dd conv=fsync bs=8M if=/dev/zero of=/dev/mmcblk0
        fi
    fi
    color_echo green '擦除完成'
fi
color_echo green '开始写入数据...'
color_echo BOLDyellow '请不要操作键盘等输入设备，并保持电源接通。\n切勿中断此过程。'
if [ -f firmware.img ] ; then
    ./busybox dd conv=fsync bs=8M if=/tmp/uploads/firmware.img of=/dev/mmcblk0
elif [ -f firmware.img.gz ] ; then
    ./busybox gzip -dc firmware.img.gz | ./busybox dd conv=fsync bs=8M of=/dev/mmcblk0
fi
color_echo green '刷机完成，稍后将执行重启...'
color_echo BOLDgreen '开始重启...'
echo b > /proc/sysrq-trigger
