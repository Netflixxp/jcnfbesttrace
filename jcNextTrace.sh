#!/bin/bash
# shellcheck disable=SC2034 # Unused variables (ISP, ip, ISP_name are globally set)

# --- 配置 ---
# 工作目录
WORKDIR="/home/tstrace"
# ISP节点配置文件名
ISP_CONFIG_FILE_NAME="isp_nodes.conf"
# ISP节点配置文件的下载URL (请确保这个URL是正确的)
ISP_CONFIG_DOWNLOAD_URL="https://raw.githubusercontent.com/Netflixxp/jcnfbesttrace/main/isp_nodes.conf" # 使用直接的main分支链接

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
# Version: 0.1.1 (Optimized Deps)
#======================================
${Font_suffix}"
}

check_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ---核心功能函数---
check_system_deps(){
    echo -e "${Info} 正在检测并安装核心依赖 (wget, curl)..."
    local pkgs_to_install="wget curl"
    local pkg_manager_update=""
    local pkg_manager_install=""
    local system_detected=0

    # 优先使用 /etc/os-release
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        SYSTEM_ID="${ID}"
        SYSTEM_ID_LIKE="${ID_LIKE}"
        system_detected=1
    elif [ -f /etc/lsb-release ]; then # 兼容旧版 Ubuntu/Debian
        # shellcheck disable=SC1091
        . /etc/lsb-release
        SYSTEM_ID="${DISTRIB_ID,,}" # 转小写
        SYSTEM_ID_LIKE=""
        system_detected=1
    else # 其他检测方法
        if grep -qiE "debian|ubuntu" /etc/issue || grep -qiE "debian|ubuntu" /proc/version; then
            SYSTEM_ID="debian"
            system_detected=1
        elif grep -qiE "centos|red hat|fedora|almalinux|rocky" /etc/issue || grep -qiE "centos|red hat|fedora|almalinux|rocky" /proc/version; then
            SYSTEM_ID="centos" # 统称为centos类
            system_detected=1
        fi
    fi

    if [ "$system_detected" -eq 0 ]; then
        echo -e "${Error} 无法确定操作系统类型来自动安装依赖。"
        echo -e "${Info} 请确保已手动安装: ${pkgs_to_install}"
        # 在这种情况下，我们无法自动安装，可以选择退出或让用户尝试
        # 为了脚本的健壮性，如果无法确定系统，依赖又很重要，最好退出
        exit 1
    fi

    # 根据检测到的系统设置包管理器命令
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
        pkg_manager_install="yum install -y -q" # yum 通常不需要单独 update
    else
        # 如果上面的检测逻辑覆盖不全，但 system_detected=1 (例如通过 /etc/issue 等)
        # 可以尝试通用的包管理器检查
        echo -e "${Warning} 系统 (${SYSTEM_ID}) 未精确匹配，尝试通用包管理器..."
        if check_command_exists apt-get; then
             pkg_manager_update="apt-get update -qq"; pkg_manager_install="apt-get install -y -qq"
        elif check_command_exists yum; then
             pkg_manager_install="yum install -y -q"
        else
            echo -e "${Error} 无法为系统 (${SYSTEM_ID}) 确定包管理器。"
            echo -e "${Info} 请手动安装: ${pkgs_to_install}"
            exit 1
        fi
    fi

    # 检查并安装缺失的依赖
    local missing_pkgs=""
    for pkg in $pkgs_to_install; do
        if ! check_command_exists "$pkg"; then
            missing_pkgs="${missing_pkgs}${pkg} "
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        echo -e "${Info} 正在安装缺失的依赖包: ${missing_pkgs}..."
        if [ -n "$pkg_manager_update" ]; then
            # echo -e "${Info} Running: $pkg_manager_update" # Debug
            $pkg_manager_update
        fi
        # echo -e "${Info} Running: $pkg_manager_install $missing_pkgs" # Debug
        if ! $pkg_manager_install $missing_pkgs; then
            echo -e "${Error} 依赖安装失败 (${missing_pkgs})。请检查包管理器或手动安装。"
            exit 1
        fi
        # 再次检查是否安装成功
        for pkg in $missing_pkgs; do
            if ! check_command_exists "$pkg"; then
                echo -e "${Error} 依赖 ${pkg} 安装后仍未找到！"
                exit 1
            fi
        done
    fi
    echo -e "${Info} 核心依赖检查和安装完成 (wget, curl)。"
}


check_root(){
    # NextTrace 安装脚本通常需要 root 权限写入 /usr/local/bin
    if [[ "$(id -u)" != "0" ]]; then
        # 只在需要安装 NextTrace 时才严格要求 root
        if ! check_command_exists nexttrace; then
            echo -e "${Error} NextTrace 未安装，其安装过程需要 root 权限。"
            echo -e "${Info} 请使用 sudo 运行此脚本，或以 root 用户身份运行。"
            exit 1
        else
            echo -e "${Warning} 非 root 用户运行。如果需要更新 NextTrace，可能需要 root 权限。"
        fi
    fi
}

setup_directory(){
    echo -e "${Info} 正在设置工作目录 (用于日志和配置文件): ${WORKDIR}"
    if ! mkdir -p "${WORKDIR}"; then
        echo -e "${Error} 无法创建工作目录 ${WORKDIR}。"
        exit 1
    fi
}

load_isp_config() {
    echo -e "${Info} 正在准备并获取最新的ISP节点配置文件: ${ISP_CONFIG_FILE_NAME}"
    local config_path_in_workdir="${WORKDIR}/${ISP_CONFIG_FILE_NAME}"

    echo -e "${Info} 尝试从 ${ISP_CONFIG_DOWNLOAD_URL} 下载最新的配置文件到 ${config_path_in_workdir}..."

    if wget -q -O "${config_path_in_workdir}" "${ISP_CONFIG_DOWNLOAD_URL}"; then
        echo -e "${Info} ${ISP_CONFIG_FILE_NAME} 下载/更新成功。"
    else
        echo -e "${Error} 下载最新的 ${ISP_CONFIG_FILE_NAME} 失败！"
        echo -e "${Info} 请确保下载链接 ${ISP_CONFIG_DOWNLOAD_URL} 正确且可访问。"
        echo -e "${Error} 无法获取最新配置文件，脚本无法继续。"
        exit 1
    fi

    if [[ ! -f "${config_path_in_workdir}" ]]; then
        echo -e "${Error} ISP节点配置文件 ${ISP_CONFIG_FILE_NAME} 下载后仍未找到！这是一个意外错误。"
        exit 1
    fi

    echo -e "${Info} 正在从 ${config_path_in_workdir} 加载节点配置..."
    ISP_NODES=()
    while IFS=';' read -r isp_code node_num node_name_val node_ip_val || [[ -n "$isp_code" ]]; do
        isp_code=$(echo "$isp_code" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
        node_name_val=$(echo "$node_name_val" | tr -d '\r')
        node_ip_val=$(echo "$node_ip_val" | tr -d '\r')

        if [[ -z "$isp_code" || "$isp_code" == \#* ]]; then
            continue
        fi

        if [[ ! "$isp_code" =~ ^[1-4]$ || ! "$node_num" =~ ^[0-9]+$ || -z "$node_name_val" || -z "$node_ip_val" ]]; then
            echo -e "${Warning} 配置文件中发现无效行: ${isp_code};${node_num};${node_name_val};${node_ip_val} (已跳过)"
            continue
        fi
        ISP_NODES+=("${isp_code};${node_num};${node_name_val};${node_ip_val}")
    done < "${config_path_in_workdir}"

    if [ ${#ISP_NODES[@]} -eq 0 ]; then
        echo -e "${Error} ISP节点配置文件 (${config_path_in_workdir}) 为空或格式不正确！"
        exit 1
    fi
    echo -e "${Info} ISP节点配置加载完成，共 ${#ISP_NODES[@]} 个节点。"
}

install_nexttrace(){
    echo -e "${Info} 正在检查并准备 NextTrace 工具..."
    if check_command_exists nexttrace; then
        echo -e "${Info} NextTrace 已安装 (版本: $(nexttrace -V 2>/dev/null || echo '未知'))。"
        return 0
    fi

    echo -e "${Info} NextTrace 未安装，尝试使用官方脚本安装 (中国镜像)..."
    # check_root 函数应该在此之前已确保有 root 权限（如果需要安装）
    if curl -fsSL nxtrace.org/nt | bash -s -- --china; then
        echo -e "${Info} NextTrace 安装成功。"
        if ! check_command_exists nexttrace; then
            echo -e "${Error} NextTrace 安装后仍未在 PATH 中找到。请检查安装过程或手动将其路径添加到 PATH。"
            echo -e "${Info} 通常安装在 /usr/local/bin/nexttrace"
            exit 1
        fi
        echo -e "${Info} NextTrace 版本: $(nexttrace -V 2>/dev/null || echo '未知')"
    else
        echo -e "${Error} NextTrace 安装失败。请尝试手动安装或检查网络。"
        echo -e "${Info} 手动安装命令: curl nxtrace.org/nt | bash"
        exit 1
    fi
}

print_separator() {
    printf "%-70s\n" "-" | sed 's/\s/-/g'
}

test_single(){
    echo -e "${Info} 请输入你要测试的目标 IP 地址:"
    read -p "输入 IP 地址: " target_ip

    while [[ -z "${target_ip}" ]]; do
        echo -e "${Error} 输入无效，IP地址不能为空。"
        read -p "请重新输入 IP 地址: " target_ip
    done
    
    print_separator
    echo -e "${Info} 正在使用 NextTrace 测试到 ${target_ip} ..."
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
    ISP="" ip="" ISP_name="" # 清理全局变量
    if ! select_isp_and_node; then
        echo -e "${Warning} 未选择有效的测试节点或操作取消，返回主菜单。"
        return
    fi
    # select_isp_and_node 成功后会设置 ip 和 ISP_name
    if [[ -n "$ip" && -n "$ISP_name" ]]; then
        result_alternative
    else
        # 理论上 select_isp_and_node 返回0时，ip和ISP_name应该已设置
        echo -e "${Warning} 内部错误：节点选择后变量未正确设置，返回主菜单。"
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
        local old_ifs="$IFS"
        IFS=';' read -r current_isp_code node_num node_name_val node_ip_val <<< "$node_data"
        IFS="$old_ifs"

        if [[ "$current_isp_code" == "$selected_isp_code" ]]; then
            count=$((count + 1))
            echo -e "${count}. ${node_name_val} (${node_ip_val})"
            current_isp_node_options+=("${node_name_val};${node_ip_val}")
        fi
    done

    if [ ${#current_isp_node_options[@]} -eq 0 ]; then
        echo -e "${Error} 没有为所选运营商 (${selected_isp_code}) 找到配置的节点。"
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
    local old_ifs_final="$IFS"
    IFS=';' read -r ISP_name ip <<< "$chosen_node_data" # ISP_name 和 ip 是全局的
    IFS="$old_ifs_final"
    return 0
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
    nexttrace -q 1 "${target_ip}"
    print_separator
    echo -e "${Info} 测试路由 到 ${current_isp_name} (${target_ip}) 完成 ！"
}

test_all(){
    echo -e "${Info} 开始四网路由快速测试 (选取各ISP的第一个配置节点)..."
    local tested_isps_codes=()
    local nodes_to_test=()
    local node_data current_ip current_name isp_code_val is_already_added_for_this_isp_code tested_code

    for node_data in "${ISP_NODES[@]}"; do
        # 确保 IFS 在这里正确设置以分割 node_data
        local old_ifs_ta="$IFS"
        IFS=';' read -r isp_code_val _ node_name_val node_ip_val <<< "$node_data"
        IFS="$old_ifs_ta"

        is_already_added_for_this_isp_code=0
        for tested_code in "${tested_isps_codes[@]}"; do
            if [[ "$tested_code" == "$isp_code_val" ]]; then
                is_already_added_for_this_isp_code=1; break;
            fi
        done
        if [[ "$is_already_added_for_this_isp_code" -eq 0 ]]; then
            nodes_to_test+=("${node_ip_val};${node_name_val}")
            tested_isps_codes+=("$isp_code_val")
        fi
        if [ ${#tested_isps_codes[@]} -ge 4 ]; then break; fi
    done
    
    if [ ${#nodes_to_test[@]} -eq 0 ]; then
        echo -e "${Warning} 配置文件中没有找到足够的节点进行四网测试。"
        return
    fi

    for node_info in "${nodes_to_test[@]}"; do
         local old_ifs_ti="$IFS"
         IFS=';' read -r current_ip current_name <<< "$node_info"
         IFS="$old_ifs_ti"
         result_all_helper "${current_ip}" "${current_name}"
    done
    echo -e "${Info} 四网路由快速测试已完成！"
}

# --- 主执行逻辑 ---
main(){
    echo_header
    check_system_deps # 安装 wget, curl (如果需要)
    check_root        # 检查 root 权限 (如果需要安装 NextTrace)
    setup_directory
    load_isp_config   # 会尝试下载 isp_nodes.conf 如果不存在或强制更新
    install_nexttrace # 安装 NextTrace (如果需要)

    while true; do
        echo -e "\n${Info} 选择你要使用的功能: "
        echo -e "1. 选择一个运营商进行测试"
        echo -e "2. 四网路由快速测试"
        echo -e "3. 手动输入 IP 进行测试"
        echo -e "4. 重新加载ISP配置文件 (从URL强制更新)"
        echo -e "5. 更新 NextTrace (使用官方脚本)"
        echo -e "6. 退出脚本"
        read -p "输入数字以选择 (1-6): " function_choice

        case "${function_choice}" in
            1) test_alternative ;;
            2) test_all | tee -a -i "${WORKDIR}/jcnxtrace.log" ;;
            3) test_single ;;
            4) load_isp_config ;; # 强制从URL重新加载
            5) 
                echo -e "${Info} 尝试更新 NextTrace..."
                # 更新 NextTrace 可能需要 root
                if [[ "$(id -u)" != "0" ]]; then
                    echo -e "${Warning} 更新 NextTrace 需要 root 权限。请使用 sudo 或以 root 用户身份运行更新命令。"
                    echo -e "${Info} 你可以尝试手动运行: sudo curl -fsSL nxtrace.org/nt | sudo bash -s -- --china"
                else
                    if curl -fsSL nxtrace.org/nt | bash -s -- --china; then
                        echo -e "${Info} NextTrace 更新/安装脚本执行完毕。"
                        echo -e "${Info} NextTrace 版本: $(nexttrace -V 2>/dev/null || echo '未知')"
                    else
                        echo -e "${Error} NextTrace 更新/安装脚本执行失败。"
                    fi
                fi
                ;;
            6) echo -e "${Info} 正在退出脚本..." ; exit 0 ;;
            *) echo -e "${Error} 输入无效或缺失！请重新选择。" ;;
        esac
        # 清理可能在 test_alternative 中设置的全局变量
        ip=""
        ISP_name=""
    done
}

# 执行主函数
main
