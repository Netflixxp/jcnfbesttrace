#!/bin/bash
# shellcheck disable=SC2034 # Unused variables (ISP, ip, ISP_name are globally set)

# --- 配置 ---
# 工作目录
WORKDIR="/home/tstrace"
# ISP节点配置文件名
ISP_CONFIG_FILE_NAME="isp_nodes.conf" # 只保留文件名
# ISP节点配置文件的下载URL (如果本地不存在)
ISP_CONFIG_DOWNLOAD_URL="https://raw.githubusercontent.com/Netflixxp/jcnfbesttrace/refs/heads/main/isp_nodes.conf"

# besttrace 下载相关
BESTTRACE_ZIP_URL="https://cdn.ipip.net/17mon/besttrace4linux.zip"
BESTTRACE_ZIP_NAME="besttrace4linux.zip"
BESTTRACE_EXE_NAME="besttrace"

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
# Project: jctestrace (外部IP配置版 - 自动下载配置)
# Version: 0.0.4
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
    elif grep -qi "centos" /etc/issue; then # Very basic fallback
        SYSTEM_ID="centos"; SYSTEM_ID_LIKE="rhel fedora"
    else
        echo -e "${Error} 无法确定操作系统。" && exit 1
    fi

    local pkgs_to_install="traceroute mtr unzip wget" # 确保 wget 也在检查列表
    local pkg_manager_update=""
    local pkg_manager_install=""

    if [[ "$SYSTEM_ID" == "debian" || "$SYSTEM_ID" == "ubuntu" || "$SYSTEM_ID_LIKE" == *"debian"* ]]; then
        pkg_manager_update="apt-get update -qq"
        pkg_manager_install="apt-get install -y -qq"
    elif [[ "$SYSTEM_ID" == "centos" || \
            "$SYSTEM_ID" == "rhel" || \
            "$SYSTEM_ID" == "fedora" || \
            "$SYSTEM_ID" == "almalinux" || \
            "$SYSTEM_ID" == "rocky" || \
            "$SYSTEM_ID_LIKE" == *"rhel"* || \
            "$SYSTEM_ID_LIKE" == *"fedora"* ]]; then
        pkgs_to_install="${pkgs_to_install//unzip/unzip tar gzip wget}"
        pkg_manager_install="yum install -y -q"
    else
        echo -e "${Error} 系统 ${SYSTEM_ID} 不被此自动安装脚本支持！"
        echo -e "${Info} 请手动安装: traceroute, mtr, unzip, wget 后重试。"
        exit 1
    fi

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
    echo -e "${Info} 正在准备ISP节点配置文件: ${ISP_CONFIG_FILE_NAME}"
    local config_path_in_workdir="${WORKDIR}/${ISP_CONFIG_FILE_NAME}"
    local SCRIPT_DIR # Will be set if needed
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" # Get script's own directory
    local config_path_in_scriptdir="${SCRIPT_DIR}/${ISP_CONFIG_FILE_NAME}"

    local effective_config_path=""

    # 检查文件是否存在于工作目录或脚本目录
    if [[ -f "${config_path_in_workdir}" ]]; then
        effective_config_path="${config_path_in_workdir}"
        echo -e "${Info} 在工作目录找到 ${ISP_CONFIG_FILE_NAME}。"
    elif [[ -f "${config_path_in_scriptdir}" ]]; then
        effective_config_path="${config_path_in_scriptdir}"
        echo -e "${Info} 在脚本目录找到 ${ISP_CONFIG_FILE_NAME}。"
    fi

    # 如果文件不存在于任何已知位置，则尝试下载
    if [[ -z "${effective_config_path}" ]]; then
        echo -e "${Warning} ISP节点配置文件 ${ISP_CONFIG_FILE_NAME} 未在本地找到。"
        echo -e "${Info} 尝试从 ${ISP_CONFIG_DOWNLOAD_URL} 下载..."
        # 下载到工作目录
        if wget -q -O "${config_path_in_workdir}" "${ISP_CONFIG_DOWNLOAD_URL}"; then
            echo -e "${Info} ${ISP_CONFIG_FILE_NAME} 下载成功到 ${config_path_in_workdir}。"
            effective_config_path="${config_path_in_workdir}"
        else
            echo -e "${Error} 下载 ${ISP_CONFIG_FILE_NAME} 失败！"
            echo -e "${Info} 请确保下载链接 ${ISP_CONFIG_DOWNLOAD_URL} 正确且可访问，"
            echo -e "${Info} 或者手动将 ${ISP_CONFIG_FILE_NAME} 放置于 ${WORKDIR} 或脚本目录。"
            exit 1
        fi
    fi

    # 再次确认文件存在
    if [[ ! -f "${effective_config_path}" ]]; then
        echo -e "${Error} ISP节点配置文件 ${ISP_CONFIG_FILE_NAME} 最终仍未找到！"
        exit 1
    fi

    echo -e "${Info} 正在从 ${effective_config_path} 加载节点配置..."
    # 清空旧数据
    ISP_NODES=()
    # 读取配置文件
    while IFS=';' read -r isp_code node_num node_name_val node_ip_val || [[ -n "$isp_code" ]]; do
        isp_code=$(echo "$isp_code" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
        node_name_val=$(echo "$node_name_val" | tr -d '\r')
        node_ip_val=$(echo "$node_ip_val" | tr -d '\r')

        if [[ -z "$isp_code" || "$isp_code" == \#* ]]; then continue; fi
        if [[ ! "$isp_code" =~ ^[1-4]$ || ! "$node_num" =~ ^[0-9]+$ || -z "$node_name_val" || -z "$node_ip_val" ]]; then
            echo -e "${Warning} 配置文件中发现无效行: ${isp_code};${node_num};${node_name_val};${node_ip_val} (已跳过)"
            continue
        fi
        ISP_NODES+=("${isp_code};${node_num};${node_name_val};${node_ip_val}")
    done < "${effective_config_path}"

    if [ ${#ISP_NODES[@]} -eq 0 ]; then
        echo -e "${Error} ISP节点配置文件为空或格式不正确！"
        exit 1
    fi
    echo -e "${Info} ISP节点配置加载完成，共 ${#ISP_NODES[@]} 个节点。"
}


install_besttrace(){
    echo -e "${Info} 正在检查并准备 besttrace 工具..."
    # 检查 WORKDIR 下的 besttrace
    if [[ -f "${WORKDIR}/${BESTTRACE_EXE_NAME}" && -x "${WORKDIR}/${BESTTRACE_EXE_NAME}" ]]; then
        echo -e "${Info} ${BESTTRACE_EXE_NAME} 已在 ${WORKDIR} 且可执行。"
        return 0
    fi

    echo -e "${Info} 正在下载 ${BESTTRACE_ZIP_NAME} 从 ${BESTTRACE_ZIP_URL} 到 ${WORKDIR}..."
    if ! wget -q -c -O "${WORKDIR}/${BESTTRACE_ZIP_NAME}" "${BESTTRACE_ZIP_URL}"; then
        echo -e "${Error} 下载 ${BESTTRACE_ZIP_NAME} 失败。请检查网络或URL。"
        rm -f "${WORKDIR}/${BESTTRACE_ZIP_NAME}"
        exit 1
    fi

    echo -e "${Info} 正在解压 ${WORKDIR}/${BESTTRACE_ZIP_NAME}..."
    local temp_dir_for_unzip="${WORKDIR}/besttrace_temp_dir"
    rm -rf "${temp_dir_for_unzip}" # 清理旧的解压目录
    mkdir -p "${temp_dir_for_unzip}"
    if ! unzip -q -o "${WORKDIR}/${BESTTRACE_ZIP_NAME}" -d "${temp_dir_for_unzip}"; then
        echo -e "${Error} 解压 ${BESTTRACE_ZIP_NAME} 失败。"
        rm -f "${WORKDIR}/${BESTTRACE_ZIP_NAME}"
        rm -rf "${temp_dir_for_unzip}"
        exit 1
    fi

    local found_exe
    found_exe=$(find "${temp_dir_for_unzip}" -name "${BESTTRACE_EXE_NAME}" -type f -executable 2>/dev/null | head -n 1)
    if [[ -z "$found_exe" ]]; then
        found_exe=$(find "${temp_dir_for_unzip}" -name "${BESTTRACE_EXE_NAME}" -type f 2>/dev/null | head -n 1)
    fi

    if [[ -n "$found_exe" && -f "$found_exe" ]]; then
        echo -e "${Info} 找到 ${BESTTRACE_EXE_NAME} at ${found_exe}."
        if ! mv "$found_exe" "${WORKDIR}/${BESTTRACE_EXE_NAME}"; then
             echo -e "${Error} 移动 ${BESTTRACE_EXE_NAME} 失败。"
             rm -f "${WORKDIR}/${BESTTRACE_ZIP_NAME}"
             rm -rf "${temp_dir_for_unzip}"
             exit 1
        fi
        chmod +x "${WORKDIR}/${BESTTRACE_EXE_NAME}"
        echo -e "${Info} ${BESTTRACE_EXE_NAME} 已准备就绪于 ${WORKDIR}。"
    else
        echo -e "${Error} 在解压文件中未找到名为 ${BESTTRACE_EXE_NAME} 的可执行文件。"
        echo -e "${Info} 请检查解压后的文件结构或确认 ${BESTTRACE_EXE_NAME} 的正确名称。"
        rm -f "${WORKDIR}/${BESTTRACE_ZIP_NAME}"
        rm -rf "${temp_dir_for_unzip}"
        exit 1
    fi

    rm -f "${WORKDIR}/${BESTTRACE_ZIP_NAME}"
    rm -rf "${temp_dir_for_unzip}"
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
    "${WORKDIR}/${BESTTRACE_EXE_NAME}" -q1 -g cn "${target_ip}" | tee -a -i "${WORKDIR}/tstrace.log"
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
    [[ "${whether_repeat_single}" == "2" ]] && echo -e "${Info} 返回主菜单..."
}


test_alternative(){
    ISP=""
    ip=""
    ISP_name=""
    if ! select_isp_and_node; then # 如果选择失败 (例如没有节点)
        echo -e "${Warning} 未选择有效的测试节点或操作取消，返回主菜单。"
        return
    fi
    if [[ -n "$ip" && -n "$ISP_name" ]]; then
        result_alternative
    else
        echo -e "${Warning} 未选择有效的测试节点，返回主菜单。"
    fi
}

select_isp_and_node(){
    echo -e "${Info} 选择需要测速的目标网络:"
    echo -e "1. 中国电信\n2. 中国联通\n3. 中国移动\n4. 教育网"
    read -p "输入数字以选择运营商 (1-4), 或输入 'q' 返回主菜单:" selected_isp_code

    if [[ "$selected_isp_code" == "q" || "$selected_isp_code" == "Q" ]]; then return 1; fi

    while [[ ! "${selected_isp_code}" =~ ^[1-4]$ ]]; do
        echo -e "${Error} 无效输入！"
        read -p "请重新选择运营商 (1-4), 或输入 'q' 返回主菜单:" selected_isp_code
        if [[ "$selected_isp_code" == "q" || "$selected_isp_code" == "Q" ]]; then return 1; fi
    done

    local count=0
    declare -a current_isp_node_options
    echo -e "${Info} 可用节点:"
    for node_data in "${ISP_NODES[@]}"; do
        IFS=';' read -r current_isp_code node_num node_name_val node_ip_val <<< "$node_data"
        if [[ "$current_isp_code" == "$selected_isp_code" ]]; then
            count=$((count + 1))
            echo -e "${count}. ${node_name_val} (${node_ip_val})"
            current_isp_node_options+=("${node_name_val};${node_ip_val}")
        fi
    done

    if [ ${#current_isp_node_options[@]} -eq 0 ]; then
        echo -e "${Error} 没有为所选运营商找到配置的节点。"
        return 1
    fi

    read -p "输入数字以选择节点 (1-${count}), 或输入 'q' 返回上级菜单:" selected_node_index
    if [[ "$selected_node_index" == "q" || "$selected_node_index" == "Q" ]]; then return 1; fi

    while ! [[ "${selected_node_index}" =~ ^[0-9]+$ && "${selected_node_index}" -ge 1 && "${selected_node_index}" -le "${count}" ]]; do
        echo -e "${Error} 无效输入！"
        read -p "请重新选择节点 (1-${count}), 或输入 'q' 返回上级菜单:" selected_node_index
        if [[ "$selected_node_index" == "q" || "$selected_node_index" == "Q" ]]; then return 1; fi
    done

    local chosen_node_data="${current_isp_node_options[$((selected_node_index - 1))]}"
    IFS=';' read-r ISP_name ip <<< "$chosen_node_data"
    return 0
}

result_alternative(){
    echo -e "${Info} 正在测试路由到 ${ISP_name} (${ip}) ..."
    "${WORKDIR}/${BESTTRACE_EXE_NAME}" -q1 -g cn "${ip}" | tee -a -i "${WORKDIR}/tstrace.log"
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
    [[ "${whether_repeat_alternative}" == "2" ]] && echo -e "${Info} 返回主菜单..."
}


result_all_helper(){
    local target_ip="$1"
    local current_isp_name="$2"
    echo -e "${Info} 测试路由 到 ${current_isp_name} (${target_ip}) 中 ..."
    "${WORKDIR}/${BESTTRACE_EXE_NAME}" -q1 -g cn "${target_ip}"
    echo -e "${Info} 测试路由 到 ${current_isp_name} (${target_ip}) 完成 ！"
}

test_all(){
    echo -e "${Info} 开始四网路由快速测试 (选取各ISP的第一个配置节点)..."
    local tested_isps_codes=()
    local nodes_to_test=()

    for node_data in "${ISP_NODES[@]}"; do
        IFS=';' read -r isp_code_val _ node_name_val node_ip_val <<< "$node_data"
        is_already_added_for_this_isp_code=0
        for tested_code in "${tested_isps_codes[@]}"; do
            if [[ "$tested_code" == "$isp_code_val" ]]; then
                is_already_added_for_this_isp_code=1; break; fi; done
        if [[ "$is_already_added_for_this_isp_code" -eq 0 ]]; then
            nodes_to_test+=("${node_ip_val};${node_name_val}")
            tested_isps_codes+=("$isp_code_val"); fi
        if [ ${#tested_isps_codes[@]} -ge 4 ]; then break; fi; done
    
    if [ ${#nodes_to_test[@]} -eq 0 ]; then
        echo -e "${Warning} 配置文件中没有找到足够的节点进行四网测试。"
        return
    fi

    for node_info in "${nodes_to_test[@]}"; do
         IFS=';' read -r current_ip current_name <<< "$node_info"
         result_all_helper "${current_ip}" "${current_name}"; done
    echo -e "${Info} 四网路由快速测试已完成！"
}

# --- 主执行逻辑 ---
main(){
    echo_header
    check_root
    check_system # 确保 wget 已安装
    setup_directory # cd 到 WORKDIR
    load_isp_config # 会尝试下载 isp_nodes.conf 如果不存在
    install_besttrace # 安装 besttrace 到 WORKDIR

    while true; do
        echo -e "\n${Info} 选择你要使用的功能: "
        echo -e "1. 选择一个运营商进行测试 (从 ${ISP_CONFIG_FILE_NAME} 加载)"
        echo -e "2. 四网路由快速测试 (从 ${ISP_CONFIG_FILE_NAME} 选取代表节点)"
        echo -e "3. 手动输入 IP 进行测试"
        echo -e "4. 重新加载ISP配置文件 (${ISP_CONFIG_FILE_NAME})"
        echo -e "5. 退出脚本"
        read -p "输入数字以选择 (1-5): " function_choice

        case "${function_choice}" in
            1) test_alternative ;;
            2) test_all | tee -a -i "${WORKDIR}/tstrace.log" ;;
            3) test_single ;;
            4) load_isp_config ;; # 重新加载，如果本地没有会再次尝试下载
            5) echo -e "${Info} 正在退出脚本..." ; exit 0 ;;
            *) echo -e "${Error} 输入无效或缺失！请重新选择。" ;;
        esac
        ip=""; ISP_name="" # 清理全局变量
    done
}

# 执行主函数
main
