#!/bin/bash
# shellcheck disable=SC2034 # Unused variables (ISP, ip, ISP_name are globally set)

# --- 配置 ---
# 工作目录
WORKDIR="/home/tstrace" # nexttrace 不需要特定的工作目录来存放可执行文件，但日志会在这里
# ISP节点配置文件名
ISP_CONFIG_FILE_NAME="isp_nodes.conf"
# ISP节点配置文件的下载URL
ISP_CONFIG_DOWNLOAD_URL="https://raw.githubusercontent.com/Netflixxp/jcnfbesttrace/refs/heads/main/isp_nodes.conf"

# --- 颜色和输出定义 ---
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
Green_font="\033[32m" && Red_font="\033[31m" && Yellow_font="\033[33m" && Font_suffix="\033[0m"
Info="${Green_font}[Info]${Font_suffix}"
Error="${Red_font}[Error]${Font_suffix}"
Warning="${Yellow_font}[Warning]${Font_suffix}"

# --- 全局变量声明 ---
declare -a ISP_NODES
declare ISP ip ISP_name

# --- 辅助函数 ---
echo_header(){
    echo -e "${Green_font}
#======================================
# Project: jcNextTrace (基于NextTrace)
# Version: 0.1.0
#======================================
${Font_suffix}"
}

check_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ---核心功能函数---
check_system_deps(){ # 重命名以反映其目的
    echo -e "${Info} 正在检测系统并安装依赖 (wget, curl)..."
    local pkgs_to_install="wget curl" # nexttrace安装需要curl, 配置文件下载需要wget
    local pkg_manager_update=""
    local pkg_manager_install=""

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
    # ... (其他系统检测逻辑可以保持或简化，因为主要依赖是 wget 和 curl)
    else # 简化的后备
        if grep -qiE "debian|ubuntu" /etc/issue || grep -qiE "debian|ubuntu" /proc/version; then
            SYSTEM_ID="debian"
        elif grep -qiE "centos|red hat|fedora" /etc/issue || grep -qiE "centos|red hat|fedora" /proc/version; then
            SYSTEM_ID="centos"
        else
            echo -e "${Error} 无法确定操作系统类型来自动安装依赖。"
            echo -e "${Info} 请确保已安装: wget, curl"
            # return 1 # 或者直接 exit 1
        fi
    fi


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
        pkg_manager_install="yum install -y -q"
    else
        echo -e "${Warning} 未知的Linux发行版 (${SYSTEM_ID})。尝试通用包管理器命令。"
        # 尝试常见的包管理器，如果失败则提示用户手动安装
        if check_command_exists apt-get; then
             pkg_manager_update="apt-get update -qq"; pkg_manager_install="apt-get install -y -qq"
        elif check_command_exists yum; then
             pkg_manager_install="yum install -y -q"
        else
            echo -e "${Error} 无法确定包管理器。"
            echo -e "${Info} 请手动安装: ${pkgs_to_install}"
            # return 1 # 或者 exit 1
        fi
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
            echo -e "${Error} 依赖安装失败 (${pkgs_to_install})。请检查或手动安装。"
            exit 1 # 关键依赖失败则退出
        fi
    fi
    echo -e "${Info} 依赖检查完成 (wget, curl)。"
}


check_root(){
    # nexttrace 安装脚本 (curl nxtrace.org/nt | bash) 可能需要 root 权限来写入 /usr/local/bin
    # 但如果用户已经安装了，或者安装到用户目录，则可能不需要。
    # 为了保险起见，如果需要执行安装命令，保留 root 检查。
    # 如果只是运行 nexttrace，通常不需要 root。
    # 此处暂时保留，因为安装步骤在脚本中。
    [[ "$(id -u)" != "0" ]] && echo -e "${Error} 脚本的某些安装步骤可能需要 root 权限！" # 提示而非强制退出
}

setup_directory(){
    echo -e "${Info} 正在设置工作目录 (用于日志和配置文件): ${WORKDIR}"
    [[ ! -d "${WORKDIR}" ]] && mkdir -p "${WORKDIR}"
    # 不需要 cd 到 WORKDIR，因为 nexttrace 是全局命令，日志可以指定路径
    # 但如果配置文件下载到 WORKDIR，后续读取时需要 WORKDIR 路径
}

load_isp_config() {
    echo -e "${Info} 正在准备ISP节点配置文件: ${ISP_CONFIG_FILE_NAME}"
    # 配置文件将尝试下载到 WORKDIR
    local config_path_in_workdir="${WORKDIR}/${ISP_CONFIG_FILE_NAME}"
    local SCRIPT_DIR
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    local config_path_in_scriptdir="${SCRIPT_DIR}/${ISP_CONFIG_FILE_NAME}"
    local effective_config_path=""

    if [[ -f "${config_path_in_workdir}" ]]; then
        effective_config_path="${config_path_in_workdir}"
    elif [[ -f "${config_path_in_scriptdir}" ]]; then
        effective_config_path="${config_path_in_scriptdir}"
    fi

    if [[ -z "${effective_config_path}" ]]; then
        echo -e "${Warning} ISP节点配置文件 ${ISP_CONFIG_FILE_NAME} 未在本地找到。"
        echo -e "${Info} 尝试从 ${ISP_CONFIG_DOWNLOAD_URL} 下载到 ${config_path_in_workdir}..."
        if wget -q -O "${config_path_in_workdir}" "${ISP_CONFIG_DOWNLOAD_URL}"; then
            echo -e "${Info} ${ISP_CONFIG_FILE_NAME} 下载成功。"
            effective_config_path="${config_path_in_workdir}"
        else
            echo -e "${Error} 下载 ${ISP_CONFIG_FILE_NAME} 失败！"
            exit 1
        fi
    fi

    if [[ ! -f "${effective_config_path}" ]]; then
        echo -e "${Error} ISP节点配置文件 ${ISP_CONFIG_FILE_NAME} 最终仍未找到！"
        exit 1
    fi

    echo -e "${Info} 正在从 ${effective_config_path} 加载节点配置..."
    ISP_NODES=()
    while IFS=';' read -r isp_code node_num node_name_val node_ip_val || [[ -n "$isp_code" ]]; do
        isp_code=$(echo "$isp_code" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
        node_name_val=$(echo "$node_name_val" | tr -d '\r')
        node_ip_val=$(echo "$node_ip_val" | tr -d '\r')
        if [[ -z "$isp_code" || "$isp_code" == \#* ]]; then continue; fi
        if [[ ! "$isp_code" =~ ^[1-4]$ || ! "$node_num" =~ ^[0-9]+$ || -z "$node_name_val" || -z "$node_ip_val" ]]; then
            echo -e "${Warning} 配置文件无效行: ${isp_code};${node_num};${node_name_val};${node_ip_val}"
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


install_nexttrace(){
    echo -e "${Info} 正在检查并准备 NextTrace 工具..."
    if check_command_exists nexttrace; then
        echo -e "${Info} NextTrace 已安装 (版本: $(nexttrace -V 2>/dev/null || echo '未知'))。"
        # 可选：检查版本并提示更新，但 nxtrace.org/nt 脚本通常会处理更新
        # curl nxtrace.org/nt | bash -s -- china # 强制更新/安装中国镜像版本
        return 0
    fi

    echo -e "${Info} NextTrace 未安装，尝试使用官方脚本安装 (中国镜像)..."
    # 使用 nxtrace.org/nt 脚本安装，它会自动选择合适的版本并安装到 /usr/local/bin
    # -s 参数传递给 bash 表示从标准输入读取命令
    # -- china 参数传递给安装脚本，选择中国镜像源加速下载
    if curl -fsSL nxtrace.org/nt | bash -s -- --china; then
        echo -e "${Info} NextTrace 安装成功。"
        # 验证一下
        if ! check_command_exists nexttrace; then
            echo -e "${Error} NextTrace 安装后仍未在 PATH 中找到。请检查安装过程或手动将其路径添加到 PATH。"
            echo -e "${Info} 通常安装在 /usr/local/bin/nexttrace"
            exit 1
        fi
    else
        echo -e "${Error} NextTrace 安装失败。请尝试手动安装或检查网络。"
        echo -e "${Info} 手动安装命令: curl nxtrace.org/nt | bash"
        exit 1
    fi
}

# 辅助函数，用于在测试前后打印分隔线
print_separator() {
    printf "%-70s\n" "-" | sed 's/\s/-/g'
}

test_single(){
    echo -e "${Info} 请输入你要测试的目标 IP 地址:"
    read -p "输入 IP 地址: " target_ip

    while [[ -z "${target_ip}" ]]
        do
            echo -e "${Error} 输入无效，IP地址不能为空。"
            echo -e "${Info} 请重新输入:" && read -p "输入 IP 地址: " target_ip
        done
    
    print_separator
    echo -e "${Info} 正在使用 NextTrace 测试到 ${target_ip} ..."
    # 使用 nexttrace，-q 1 表示快速模式，发送1个包
    # nexttrace 默认输出中文地理位置，通常不需要额外参数
    # --map 参数可以在浏览器中打开地图可视化路由，但对CLI输出不直接影响
    nexttrace -q 1 "${target_ip}" | tee -a -i "${WORKDIR}/jcnxtrace.log"
    print_separator
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
    if ! select_isp_and_node; then
        echo -e "${Warning} 未选择有效的测试节点或操作取消，返回主菜单。"
        return
    fi
    if [[ -n "$ip" && -n "$ISP_name" ]]; then
        result_alternative
    else
        echo -e "${Warning} 未选择有效的测试节点，返回主菜单。" # Should not happen if select_isp_and_node succeeds
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
    declare -a current_isp_node_options # 存储当前ISP的节点选项
    echo -e "${Info} 可用节点:"
    for node_data in "${ISP_NODES[@]}"; do
        # 注意：这里 IFS 的作用域仅限于 read 命令（在某些 shell 版本中），
        # 或者如果用 < <(command) 的形式，则作用域更广。
        # 为了安全，可以在循环外保存旧的IFS，循环内设置，循环后恢复。
        # 但对于简单的 <<< here-string，通常没问题。
        local old_ifs="$IFS" # 保存旧的IFS
        IFS=';' read -r current_isp_code node_num node_name_val node_ip_val <<< "$node_data"
        IFS="$old_ifs" # 恢复旧的IFS

        if [[ "$current_isp_code" == "$selected_isp_code" ]]; then
            count=$((count + 1))
            echo -e "${count}. ${node_name_val} (${node_ip_val})"
            current_isp_node_options+=("${node_name_val};${node_ip_val}") # 存储名称和IP
        fi
    done

    if [ ${#current_isp_node_options[@]} -eq 0 ]; then
        echo -e "${Error} 没有为所选运营商找到配置的节点。"
        return 1 # 表示选择失败
    fi

    read -p "输入数字以选择节点 (1-${count}), 或输入 'q' 返回上级菜单:" selected_node_index
    if [[ "$selected_node_index" == "q" || "$selected_node_index" == "Q" ]]; then return 1; fi

    while ! [[ "${selected_node_index}" =~ ^[0-9]+$ && "${selected_node_index}" -ge 1 && "${selected_node_index}" -le "${count}" ]]; do
        echo -e "${Error} 无效输入！"
        read -p "请重新选择节点 (1-${count}), 或输入 'q' 返回上级菜单:" selected_node_index
        if [[ "$selected_node_index" == "q" || "$selected_node_index" == "Q" ]]; then return 1; fi
    done

    # 获取选择的节点信息
    local chosen_node_data="${current_isp_node_options[$((selected_node_index - 1))]}"
    # --- 此处是修改点 ---
    local old_ifs_final="$IFS" # 保存旧的IFS
    IFS=';' read -r ISP_name ip <<< "$chosen_node_data" # 修正: read -r
    IFS="$old_ifs_final" # 恢复旧的IFS
    # --------------------
    return 0 # 表示选择成功
}

result_alternative(){
    print_separator
    echo -e "${Info} 正在使用 NextTrace 测试路由到 ${ISP_name} (${ip}) ..."
    nexttrace -q 1 "${ip}" | tee -a -i "${WORKDIR}/jcnxtrace.log"
    print_separator
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
    print_separator
    echo -e "${Info} 测试路由 到 ${current_isp_name} (${target_ip}) 中 ..."
    nexttrace -q 1 "${target_ip}" # 输出将被 test_all 调用处的 tee 捕获
    print_separator
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
    check_root # 提示可能需要 root
    check_system_deps # 安装 wget, curl
    setup_directory
    load_isp_config
    install_nexttrace # 安装 NextTrace

    while true; do
        echo -e "\n${Info} 选择你要使用的功能: "
        echo -e "1. 选择一个运营商进行测试"
        echo -e "2. 四网路由快速测试)"
        echo -e "3. 手动输入 IP 进行测试"
        echo -e "4. 重新加载ISP配置文件 "
        echo -e "5. 更新 NextTrace (使用官方脚本)"
        echo -e "6. 退出脚本"
        read -p "输入数字以选择 (1-6): " function_choice

        case "${function_choice}" in
            1) test_alternative ;;
            2) test_all | tee -a -i "${WORKDIR}/jcnxtrace.log" ;;
            3) test_single ;;
            4) load_isp_config ;;
            5) echo -e "${Info} 尝试更新 NextTrace..."; curl -fsSL nxtrace.org/nt | bash -s -- --china; ;;
            6) echo -e "${Info} 正在退出脚本..." ; exit 0 ;;
            *) echo -e "${Error} 输入无效或缺失！请重新选择。" ;;
        esac
        ip=""; ISP_name="" # 清理全局变量
    done
}

# 执行主函数
main
