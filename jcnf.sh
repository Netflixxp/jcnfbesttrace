#!/bin/bash
# shellcheck disable=SC2034 # Unused variables (ISP, ip, ISP_name are globally set)

# --- 配置 ---
# 工作目录
WORKDIR="/home/tstrace"
# ISP节点配置文件名 (应与脚本在同一目录或提供完整路径)
ISP_CONFIG_FILE="isp_nodes.conf"
# besttrace 下载相关
BESTTRACE_ZIP_URL="https://cdn.ipip.net/17mon/besttrace4linux.zip"
BESTTRACE_ZIP_NAME="besttrace4linux.zip"
BESTTRACE_EXE_NAME="besttrace" # 解压后可执行文件的名字，可能因版本变化，需确认

# --- 颜色和输出定义 ---
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
Green_font="\033[32m" && Red_font="\033[31m" && Yellow_font="\033[33m" && Font_suffix="\033[0m"
Info="${Green_font}[Info]${Font_suffix}"
Error="${Red_font}[Error]${Font_suffix}"
Warning="${Yellow_font}[Warning]${Font_suffix}"

# --- 全局变量声明 (将在函数中赋值) ---
declare -a ISP_NODES # 存储从配置文件读取的节点信息
declare ISP ip ISP_name # 用于存储用户选择的ISP和节点信息

# --- 辅助函数 ---
echo_header(){
    echo -e "${Green_font}
#======================================
# Project: jctestrace (外部IP配置版)
# Version: 0.0.3
# Blog:   https://ybfl.xyz
# Github: https://github.com/Netflixxp (原始项目)
#======================================
${Font_suffix}"
}

check_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ---核心功能函数---
check_system(){
    echo -e "${Info} 正在检测系统并安装依赖..."
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        SYSTEM_ID="${ID}"
        SYSTEM_ID_LIKE="${ID_LIKE}"
    elif [ -f /etc/lsb-release ]; then
        # shellcheck disable=SC1091
        . /etc/lsb-release
        SYSTEM_ID="${DISTRIB_ID,,}"
        SYSTEM_ID_LIKE=""
    elif [ -f /etc/redhat-release ]; then
        SYSTEM_ID="centos"
        SYSTEM_ID_LIKE="rhel fedora"
    elif grep -qi "debian" /etc/issue; then
        SYSTEM_ID="debian"; SYSTEM_ID_LIKE="debian"
    elif grep -qi "ubuntu" /etc/issue; then
        SYSTEM_ID="ubuntu"; SYSTEM_ID_LIKE="debian"
    elif grep -qi "centos" /etc/issue; then
        SYSTEM_ID="centos"; SYSTEM_ID_LIKE="rhel fedora"
    else
        echo -e "${Error} 无法确定操作系统。" && exit 1
    fi

    local pkgs_to_install="traceroute mtr unzip"
    local pkg_manager_update=""
    local pkg_manager_install=""

    if [[ "$SYSTEM_ID" == "debian" || "$SYSTEM_ID" == "ubuntu" || "$SYSTEM_ID_LIKE" == *"debian"* ]]; then
        pkg_manager_update="apt-get update -qq"
        pkg_manager_install="apt-get install -y -qq"
    elif [[ "$SYSTEM_ID" == "centos" || "$SYSTEM_ID" == "rhel" || "$SYSTEM_ID" == "fedora" || "$SYSTEM_ID" == "almalinux" || "$SYSTEM_ID" == "rocky" || "$SYSTEM_ID_LIKE" == *"rhel"* || "$SYSTEM_ID_LIKE" == *"fedora"* ]]; pkgs_to_install="${pkgs_to_install//unzip/unzip tar gzip}"; # RHEL系可能需要 tar, gzip 处理其他类型的压缩包，unzip一般也有
        pkg_manager_install="yum install -y -q" # yum 通常不需要单独 update
    else
        echo -e "${Error} 系统 ${SYSTEM_ID} 不被此自动安装脚本支持！"
        echo -e "${Info} 请手动安装: traceroute, mtr, unzip 后重试。"
        exit 1
    fi

    # 安装必要的包
    needs_install=0
    for pkg in $pkgs_to_install; do
        if ! check_command_exists "$pkg"; then
            needs_install=1
            break
        fi
    done

    if [ "$needs_install" -eq 1 ]; then
        echo -e "${Info} 正在安装缺失的依赖包: ${pkgs_to_install}..."
        if [ -n "$pkg_manager_update" ]; then
            $pkg_manager_update
        fi
        if ! $pkg_manager_install $pkgs_to_install; then
            echo -e "${Error} 依赖安装失败 (${pkgs_to_install})。请检查包管理器源或手动安装。"
            exit 1
        fi
    fi
    echo -e "${Info} 依赖检查完成。"
}

check_root(){
    [[ "$(id -u)" != "0" ]] && echo -e "${Error} 必须是 root 用户才能运行此脚本！" && exit 1
}

setup_directory(){
    echo -e "${Info} 正在设置工作目录: ${WORKDIR}"
    [[ ! -d "${WORKDIR}" ]] && mkdir -p "${WORKDIR}"
    cd "${WORKDIR}" || { echo -e "${Error} 无法进入目录 ${WORKDIR}"; exit 1; }
}

load_isp_config() {
    echo -e "${Info} 正在加载ISP节点配置文件: ${ISP_CONFIG_FILE}"
    local full_config_path="${WORKDIR}/${ISP_CONFIG_FILE}"
    if [[ ! -f "${full_config_path}" ]]; then
        # 尝试从脚本所在目录加载 (如果脚本不在WORKDIR中运行)
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        full_config_path="${SCRIPT_DIR}/${ISP_CONFIG_FILE}"
        if [[ ! -f "${full_config_path}" ]]; then
            echo -e "${Error} ISP节点配置文件 ${ISP_CONFIG_FILE} 未找到！"
            echo -e "${Info} 请确保 ${ISP_CONFIG_FILE} 文件存在于脚本目录或 ${WORKDIR} 目录中。"
            echo -e "${Info} 配置文件格式示例："
            echo -e "${Info} 1;1;上海电信;1.2.3.4"
            echo -e "${Info} 2;1;北京联通;5.6.7.8"
            exit 1
        fi
    fi

    # 清空旧数据
    ISP_NODES=()
    # 读取配置文件，忽略空行和注释行
    while IFS=';' read -r isp_code node_num node_name_val node_ip_val || [[ -n "$isp_code" ]]; do
        # 去除可能的 BOM 和 回车符
        isp_code=$(echo "$isp_code" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
        node_name_val=$(echo "$node_name_val" | tr -d '\r')
        node_ip_val=$(echo "$node_ip_val" | tr -d '\r')

        if [[ -z "$isp_code" || "$isp_code" == \#* ]]; then
            continue # 跳过空行和注释
        fi
        if [[ ! "$isp_code" =~ ^[1-4]$ || ! "$node_num" =~ ^[0-9]+$ || -z "$node_name_val" || -z "$node_ip_val" ]]; then
            echo -e "${Warning} 配置文件中发现无效行: ${isp_code};${node_num};${node_name_val};${node_ip_val} (已跳过)"
            continue
        fi
        ISP_NODES+=("${isp_code};${node_num};${node_name_val};${node_ip_val}")
    done < "${full_config_path}"

    if [ ${#ISP_NODES[@]} -eq 0 ]; then
        echo -e "${Error} ISP节点配置文件为空或格式不正确！"
        exit 1
    fi
    echo -e "${Info} ISP节点配置加载完成，共 ${#ISP_NODES[@]} 个节点。"
}


install_besttrace(){
    echo -e "${Info} 正在检查并准备 besttrace 工具..."
    if [[ -f "${BESTTRACE_EXE_NAME}" && -x "${BESTTRACE_EXE_NAME}" ]]; then
        echo -e "${Info} ${BESTTRACE_EXE_NAME} 已存在且可执行。"
        return 0
    fi

    echo -e "${Info} 正在下载 ${BESTTRACE_ZIP_NAME} 从 ${BESTTRACE_ZIP_URL} ..."
    if ! wget -q -c -O "${BESTTRACE_ZIP_NAME}" "${BESTTRACE_ZIP_URL}"; then
        echo -e "${Error} 下载 ${BESTTRACE_ZIP_NAME} 失败。请检查网络或URL。"
        rm -f "${BESTTRACE_ZIP_NAME}"
        exit 1
    fi

    echo -e "${Info} 正在解压 ${BESTTRACE_ZIP_NAME}..."
    # 清理旧的解压目录（如果存在）
    rm -rf besttrace_temp_dir
    mkdir besttrace_temp_dir
    if ! unzip -q -o "${BESTTRACE_ZIP_NAME}" -d besttrace_temp_dir; then # -o: overwrite
        echo -e "${Error} 解压 ${BESTTRACE_ZIP_NAME} 失败。"
        rm -f "${BESTTRACE_ZIP_NAME}"
        rm -rf besttrace_temp_dir
        exit 1
    fi

    # 查找 besttrace 可执行文件 (它可能在子目录中，也可能直接在根目录)
    local found_exe
    found_exe=$(find besttrace_temp_dir -name "${BESTTRACE_EXE_NAME}" -type f -executable 2>/dev/null | head -n 1)
    if [[ -z "$found_exe" ]]; then # 如果没有可执行的，尝试找任何同名文件
        found_exe=$(find besttrace_temp_dir -name "${BESTTRACE_EXE_NAME}" -type f 2>/dev/null | head -n 1)
    fi


    if [[ -n "$found_exe" && -f "$found_exe" ]]; then
        echo -e "${Info} 找到 ${BESTTRACE_EXE_NAME} at ${found_exe}."
        # 将其移动到当前工作目录 (WORKDIR) 并确保可执行
        if ! mv "$found_exe" "./${BESTTRACE_EXE_NAME}"; then
             echo -e "${Error} 移动 ${BESTTRACE_EXE_NAME} 失败。"
             rm -f "${BESTTRACE_ZIP_NAME}"
             rm -rf besttrace_temp_dir
             exit 1
        fi
        chmod +x "./${BESTTRACE_EXE_NAME}"
        echo -e "${Info} ${BESTTRACE_EXE_NAME} 已准备就绪。"
    else
        echo -e "${Error} 在解压文件中未找到名为 ${BESTTRACE_EXE_NAME} 的可执行文件。"
        echo -e "${Info} 请检查解压后的文件结构或确认 ${BESTTRACE_EXE_NAME} 的正确名称。"
        rm -f "${BESTTRACE_ZIP_NAME}"
        rm -rf besttrace_temp_dir # 清理
        exit 1
    fi

    # 清理下载的zip包和临时解压目录
    rm -f "${BESTTRACE_ZIP_NAME}"
    rm -rf besttrace_temp_dir
}


test_single(){
    echo -e "${Info} 请输入你要测试的目标 IP 地址:"
    read -p "输入 IP 地址: " target_ip

    while [[ -z "${target_ip}" ]]
        do
            echo -e "${Error} 输入无效，IP地址不能为空。"
            echo -e "${Info} 请重新输入:" && read -p "输入 IP 地址: " target_ip
        done

    echo -e "${Info} 正在测试到 ${target_ip} ..."
    # 假设 ./besttrace 在当前路径 (WORKDIR)
    ./${BESTTRACE_EXE_NAME} -q1 -g cn "${target_ip}" | tee -a -i "${WORKDIR}/tstrace.log"
    repeat_test_single
}

repeat_test_single(){
    echo -e "${Info} 是否继续测试其他目标 IP ?"
    echo -e "1. 是\n2. 否"
    read -p "请选择:" whether_repeat_single
    while [[ ! "${whether_repeat_single}" =~ ^[1-2]$ ]]; do
        echo -e "${Error} 输入无效！" && read -p "请重新输入:" whether_repeat_single
    done
    [[ "${whether_repeat_single}" == "1" ]] && test_single
    [[ "${whether_repeat_single}" == "2" ]] && echo -e "${Info} 退出脚本..." && exit 0
}


test_alternative(){
    select_isp_and_node
    result_alternative
}

select_isp_and_node(){
    echo -e "${Info} 选择需要测速的目标网络:"
    echo -e "1. 中国电信\n2. 中国联通\n3. 中国移动\n4. 教育网"
    read -p "输入数字以选择运营商 (1-4):" selected_isp_code

    while [[ ! "${selected_isp_code}" =~ ^[1-4]$ ]]; do
        echo -e "${Error} 无效输入！" && read -p "请重新选择运营商 (1-4):" selected_isp_code
    done

    # 显示选定运营商的节点
    local count=0
    declare -a current_isp_node_options # 存储当前ISP的节点选项
    echo -e "${Info} 可用节点:"
    for node_data in "${ISP_NODES[@]}"; do
        IFS=';' read -r isp_code node_num node_name_val node_ip_val <<< "$node_data"
        if [[ "$isp_code" == "$selected_isp_code" ]]; then
            count=$((count + 1))
            echo -e "${count}. ${node_name_val} (${node_ip_val})"
            current_isp_node_options+=("${node_name_val};${node_ip_val}") # 存储名称和IP
        fi
    done

    if [ ${#current_isp_node_options[@]} -eq 0 ]; then
        echo -e "${Error} 没有为所选运营商找到配置的节点。"
        # 可以选择返回主菜单或退出
        return 1 # 表示选择失败
    fi

    read -p "输入数字以选择节点 (1-${count}):" selected_node_index
    while ! [[ "${selected_node_index}" =~ ^[0-9]+$ && "${selected_node_index}" -ge 1 && "${selected_node_index}" -le "${count}" ]]; do
        echo -e "${Error} 无效输入！" && read -p "请重新选择节点 (1-${count}):" selected_node_index
    done

    # 获取选择的节点信息
    # selected_node_index 是基于1的，数组索引是基于0的
    local chosen_node_data="${current_isp_node_options[$((selected_node_index - 1))]}"
    IFS=';' read-r ISP_name ip <<< "$chosen_node_data" # 设置全局变量
}

result_alternative(){
    if [[ -z "$ip" || -z "$ISP_name" ]]; then
        echo -e "${Warning} 未选择有效的测试节点。返回主菜单。"
        return
    fi
    echo -e "${Info} 正在测试路由到 ${ISP_name} (${ip}) ..."
    ./${BESTTRACE_EXE_NAME} -q1 -g cn "${ip}" | tee -a -i "${WORKDIR}/tstrace.log"
    echo -e "${Info} 到 ${ISP_name} 的路由测试完成！"
    repeat_test_alternative
}

repeat_test_alternative(){
    echo -e "${Info} 是否继续测试其他节点?"
    echo -e "1. 是 (选择其他运营商/节点)\n2. 否 (返回主菜单)"
    read -p "请选择:" whether_repeat_alternative
    while [[ ! "${whether_repeat_alternative}" =~ ^[1-2]$ ]]; do
        echo -e "${Error} 输入无效！" && read -p "请重新输入:" whether_repeat_alternative
    done
    [[ "${whether_repeat_alternative}" == "1" ]] && test_alternative
    # 如果选2，则不执行任何操作，函数结束，控制权返回到主循环
    [[ "${whether_repeat_alternative}" == "2" ]] && echo -e "${Info} 返回主菜单..."
}


result_all_helper(){
    local target_ip="$1"
    local current_isp_name="$2"
    echo -e "${Info} 测试路由 到 ${current_isp_name} (${target_ip}) 中 ..."
    ./${BESTTRACE_EXE_NAME} -q1 -g cn "${target_ip}" # 输出将被 test_all 调用处的 tee 捕获
    echo -e "${Info} 测试路由 到 ${current_isp_name} (${target_ip}) 完成 ！"
}

test_all(){
    echo -e "${Info} 开始四网路由快速测试 (选取各ISP的第一个配置节点)..."
    local tested_isps=() # 用于跟踪已测试的ISP代码
    local nodes_to_test=()

    for node_data in "${ISP_NODES[@]}"; do
        IFS=';' read -r isp_code_val _ node_name_val node_ip_val <<< "$node_data"
        is_already_added=0
        for tested_isp_code in "${tested_isps[@]}"; do
            if [[ "$tested_isp_code" == "$isp_code_val" ]]; then
                is_already_added=1
                break
            fi
        done
        if [[ "$is_already_added" -eq 0 ]]; then
            nodes_to_test+=("${node_ip_val};${node_name_val}")
            tested_isps+=("$isp_code_val")
        fi
    done
    
    if [ ${#nodes_to_test[@]} -eq 0 ]; then
        echo -e "${Warning} 配置文件中没有找到足够的节点进行四网测试。"
        return
    fi

    for node_info in "${nodes_to_test[@]}"; do
         IFS=';' read -r current_ip current_name <<< "$node_info"
         result_all_helper "${current_ip}" "${current_name}"
    done

    echo -e "${Info} 四网路由快速测试已完成！"
}

# --- 主执行逻辑 ---
main(){
    echo_header
    check_root
    check_system
    setup_directory # cd 到 WORKDIR
    load_isp_config # 加载节点
    install_besttrace # 安装 besttrace 到 WORKDIR

    while true; do
        echo -e "\n${Info} 选择你要使用的功能: "
        echo -e "1. 选择一个运营商进行测试 (从 ${ISP_CONFIG_FILE} 加载)"
        echo -e "2. 四网路由快速测试 (从 ${ISP_CONFIG_FILE} 选取代表节点)"
        echo -e "3. 手动输入 IP 进行测试"
        echo -e "4. 重新加载ISP配置文件 (${ISP_CONFIG_FILE})"
        echo -e "5. 退出脚本"
        read -p "输入数字以选择 (1-5): " function_choice

        case "${function_choice}" in
            1) test_alternative ;;
            2) test_all | tee -a -i "${WORKDIR}/tstrace.log" ;;
            3) test_single ;;
            4) load_isp_config ;;
            5) echo -e "${Info} 退出脚本..." ; exit 0 ;;
            *) echo -e "${Error} 输入无效或缺失！请重新选择。" ;;
        esac
    done
}

# 执行主函数
main
