#!/bin/bash

# GitHub复刻同步脚本 - 包含自动依赖安装、登录、仓库选择和自动同步功能
# 使用方法: ./github_fork_sync.sh

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
CONFIG_DIR="$HOME/.github_fork_sync"
CONFIG_FILE="$CONFIG_DIR/config"
TOKEN_FILE="$CONFIG_DIR/token"
REPO_CACHE_FILE="$CONFIG_DIR/repos_cache"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${PURPLE}[DEBUG]${NC} $1"
}

# 检测操作系统和包管理器
detect_os_and_pm() {
    case "$(uname -s)" in
        Darwin)
            OS="macOS"
            if command -v brew &> /dev/null; then
                PM="brew"
            else
                PM="unknown"
            fi
            ;;
        Linux)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS="$NAME"
                
                # 检测包管理器
                if command -v apt-get &> /dev/null; then
                    PM="apt"
                elif command -v dnf &> /dev/null; then
                    PM="dnf"
                elif command -v yum &> /dev/null; then
                    PM="yum"
                elif command -v pacman &> /dev/null; then
                    PM="pacman"
                elif command -v zypper &> /dev/null; then
                    PM="zypper"
                elif command -v apk &> /dev/null; then
                    PM="apk"
                else
                    PM="unknown"
                fi
            else
                OS="Linux"
                PM="unknown"
            fi
            ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*)
            OS="Windows"
            if command -v choco &> /dev/null; then
                PM="choco"
            elif command -v scoop &> /dev/null; then
                PM="scoop"
            else
                PM="unknown"
            fi
            ;;
        FreeBSD)
            OS="FreeBSD"
            if command -v pkg &> /dev/null; then
                PM="pkg"
            else
                PM="unknown"
            fi
            ;;
        OpenBSD)
            OS="OpenBSD"
            if command -v pkg_add &> /dev/null; then
                PM="pkg_add"
            else
                PM="unknown"
            fi
            ;;
        *)
            OS="Unknown"
            PM="unknown"
            ;;
    esac
    
    log_info "检测到操作系统: $OS"
    log_info "检测到包管理器: $PM"
}

# 安装包管理器（如果缺失）
install_package_manager() {
    case "$OS" in
        "macOS")
            if [ "$PM" = "unknown" ]; then
                log_info "安装 Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                PM="brew"
                log_success "Homebrew 安装完成"
            fi
            ;;
        "Ubuntu"|"Debian"|"Linux Mint")
            # apt 通常已预装
            ;;
        "CentOS"|"Red Hat"|"Fedora")
            # dnf/yum 通常已预装
            ;;
        "Arch Linux"|"Manjaro")
            # pacman 通常已预装
            ;;
        "Windows")
            if [ "$PM" = "unknown" ]; then
                log_info "Windows 系统推荐安装包管理器:"
                log_info "1. Chocolatey - 专业包管理器"
                log_info "2. Scoop - 轻量级包管理器"
                read -p "请选择要安装的包管理器 (1/2): " choice
                case $choice in
                    1)
                        log_info "安装 Chocolatey..."
                        powershell -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
                        PM="choco"
                        ;;
                    2)
                        log_info "安装 Scoop..."
                        powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser; irm get.scoop.sh | iex"
                        PM="scoop"
                        ;;
                    *)
                        log_error "未选择包管理器，无法继续"
                        exit 1
                        ;;
                esac
            fi
            ;;
        "FreeBSD")
            # pkg 通常已预装
            ;;
        "OpenBSD")
            # pkg_add 通常已预装
            ;;
        *)
            log_warning "未知操作系统，无法自动安装包管理器"
            return 1
            ;;
    esac
    return 0
}

# 安装依赖
install_dependencies() {
    log_info "检查系统依赖..."
    local missing_deps=()
    
    # 检查各个依赖
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    # 如果没有缺失的依赖，直接返回
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_success "所有依赖已安装"
        return 0
    fi
    
    log_warning "缺少以下依赖: ${missing_deps[*]}"
    
    # 如果包管理器未知，尝试安装
    if [ "$PM" = "unknown" ]; then
        install_package_manager
    fi
    
    read -p "是否自动安装这些依赖? (y/N): " confirm
    
    case $confirm in
        [yY]|[yY][eE][sS])
            log_info "开始安装依赖..."
            ;;
        *)
            log_error "请手动安装以下依赖后重新运行脚本:"
            for dep in "${missing_deps[@]}"; do
                log_info "  - $dep"
            done
            exit 1
            ;;
    esac
    
    # 根据操作系统和包管理器安装依赖
    case "$PM" in
        "brew")
            install_deps_brew "${missing_deps[@]}"
            ;;
        "apt")
            install_deps_apt "${missing_deps[@]}"
            ;;
        "dnf")
            install_deps_dnf "${missing_deps[@]}"
            ;;
        "yum")
            install_deps_yum "${missing_deps[@]}"
            ;;
        "pacman")
            install_deps_pacman "${missing_deps[@]}"
            ;;
        "zypper")
            install_deps_zypper "${missing_deps[@]}"
            ;;
        "apk")
            install_deps_apk "${missing_deps[@]}"
            ;;
        "choco")
            install_deps_choco "${missing_deps[@]}"
            ;;
        "scoop")
            install_deps_scoop "${missing_deps[@]}"
            ;;
        "pkg")
            install_deps_pkg "${missing_deps[@]}"
            ;;
        "pkg_add")
            install_deps_pkg_add "${missing_deps[@]}"
            ;;
        *)
            install_deps_fallback "${missing_deps[@]}"
            ;;
    esac
    
    # 验证安装结果
    for dep in "${missing_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "依赖安装失败: $dep"
            log_info "请手动安装后重新运行脚本"
            exit 1
        fi
    done
    
    log_success "所有依赖安装完成"
}

# 各种包管理器的安装函数
install_deps_brew() {
    log_info "使用 Homebrew 安装依赖..."
    for dep in "$@"; do
        log_info "安装 $dep..."
        brew install "$dep"
    done
}

install_deps_apt() {
    log_info "使用 APT 安装依赖..."
    sudo apt-get update
    for dep in "$@"; do
        log_info "安装 $dep..."
        sudo apt-get install -y "$dep"
    done
}

install_deps_dnf() {
    log_info "使用 DNF 安装依赖..."
    sudo dnf update -y
    for dep in "$@"; do
        log_info "安装 $dep..."
        sudo dnf install -y "$dep"
    done
}

install_deps_yum() {
    log_info "使用 YUM 安装依赖..."
    sudo yum update -y
    for dep in "$@"; do
        log_info "安装 $dep..."
        sudo yum install -y "$dep"
    done
}

install_deps_pacman() {
    log_info "使用 Pacman 安装依赖..."
    sudo pacman -Sy
    for dep in "$@"; do
        case "$dep" in
            "jq")
                sudo pacman -S --noconfirm jq
                ;;
            "git")
                sudo pacman -S --noconfirm git
                ;;
            "curl")
                sudo pacman -S --noconfirm curl
                ;;
        esac
    done
}

install_deps_zypper() {
    log_info "使用 Zypper 安装依赖..."
    sudo zypper refresh
    for dep in "$@"; do
        log_info "安装 $dep..."
        sudo zypper install -y "$dep"
    done
}

install_deps_apk() {
    log_info "使用 APK 安装依赖..."
    sudo apk update
    for dep in "$@"; do
        log_info "安装 $dep..."
        sudo apk add "$dep"
    done
}

install_deps_choco() {
    log_info "使用 Chocolatey 安装依赖..."
    for dep in "$@"; do
        log_info "安装 $dep..."
        choco install "$dep" -y
    done
}

install_deps_scoop() {
    log_info "使用 Scoop 安装依赖..."
    for dep in "$@"; do
        log_info "安装 $dep..."
        scoop install "$dep"
    done
}

install_deps_pkg() {
    log_info "使用 FreeBSD pkg 安装依赖..."
    sudo pkg update
    for dep in "$@"; do
        log_info "安装 $dep..."
        sudo pkg install -y "$dep"
    done
}

install_deps_pkg_add() {
    log_info "使用 OpenBSD pkg_add 安装依赖..."
    for dep in "$@"; do
        log_info "安装 $dep..."
        sudo pkg_add "$dep"
    done
}

# 回退安装方法（当包管理器不支持时）
install_deps_fallback() {
    log_warning "无法使用包管理器安装依赖，尝试其他方法..."
    
    for dep in "$@"; do
        case "$dep" in
            "git")
                install_git_manual
                ;;
            "curl")
                install_curl_manual
                ;;
            "jq")
                install_jq_manual
                ;;
        esac
    done
}

# 手动安装 Git
install_git_manual() {
    log_info "尝试手动安装 Git..."
    case "$OS" in
        "macOS")
            # macOS 通常预装 Git，如果没有则通过 Xcode 命令行工具安装
            xcode-select --install 2>/dev/null || log_warning "请手动安装 Xcode 命令行工具"
            ;;
        "Windows")
            log_info "请从 https://git-scm.com/download/win 下载 Git for Windows"
            ;;
        *)
            log_info "请参考 https://git-scm.com/download/linux 安装 Git"
            ;;
    esac
}

# 手动安装 Curl
install_curl_manual() {
    log_info "尝试手动安装 Curl..."
    case "$OS" in
        "Windows")
            log_info "Curl 通常包含在 Git for Windows 中"
            ;;
        *)
            log_info "请参考官方文档安装 Curl: https://curl.se/download.html"
            ;;
    esac
}

# 手动安装 jq
install_jq_manual() {
    log_info "尝试手动安装 jq..."
    
    # 尝试从源码编译安装
    if command -v gcc &> /dev/null && command -v make &> /dev/null; then
        log_info "尝试从源码编译安装 jq..."
        local temp_dir
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        # 下载 jq 源码
        if curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-1.6.tar.gz -o jq.tar.gz; then
            tar -xzf jq.tar.gz
            cd jq-1.6
            ./configure --disable-maintainer-mode
            make
            sudo make install
            cd /
            rm -rf "$temp_dir"
            return 0
        else
            log_error "下载 jq 源码失败"
        fi
    fi
    
    # 如果编译失败，提供下载链接
    case "$(uname -m)" in
        "x86_64")
            arch="amd64"
            ;;
        "aarch64"|"arm64")
            arch="arm64"
            ;;
        *)
            arch="amd64"  # 默认
            ;;
    esac
    
    log_info "请从 https://stedolan.github.io/jq/download/ 下载 jq"
    log_info "或运行: curl -L -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux-$arch && chmod +x /usr/local/bin/jq"
}

# 创建配置目录
create_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        log_info "创建配置目录: $CONFIG_DIR"
    fi
}

# GitHub认证
github_auth() {
    if [ -f "$TOKEN_FILE" ]; then
        GITHUB_TOKEN=$(cat "$TOKEN_FILE")
        if validate_token; then
            log_success "使用已保存的GitHub Token"
            return 0
        else
            log_warning "保存的Token已失效，需要重新认证"
            rm -f "$TOKEN_FILE"
        fi
    fi

    log_info "GitHub认证"
    echo "请按照以下步骤获取GitHub Personal Access Token:"
    echo "1. 访问 https://github.com/settings/tokens"
    echo "2. 点击 'Generate new token'"
    echo "3. 选择 'Generate new token (classic)'"
    echo "4. 设置备注 (如: Fork Sync Tool)"
    echo "5. 勾选以下权限:"
    echo "   - repo (全部)"
    echo "   - read:org"
    echo "   - read:user"
    echo "6. 点击 'Generate token'"
    echo ""
    
    read -p "请输入您的GitHub Personal Access Token: " GITHUB_TOKEN
    
    if [ -z "$GITHUB_TOKEN" ]; then
        log_error "Token不能为空"
        exit 1
    fi
    
    if validate_token; then
        echo "$GITHUB_TOKEN" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        log_success "Token验证成功并已保存"
    else
        log_error "Token验证失败"
        exit 1
    fi
}

# 验证Token
validate_token() {
    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/user)
    
    if echo "$response" | jq -e '.login' > /dev/null 2>&1; then
        GITHUB_USER=$(echo "$response" | jq -r '.login')
        return 0
    else
        return 1
    fi
}

# GitHub API调用
github_api() {
    local endpoint=$1
    local url="https://api.github.com$endpoint"
    
    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         -H "Accept: application/vnd.github.v3+json" \
         -H "User-Agent: GitHub-Fork-Sync-Tool" \
         "$url"
}

# 获取用户复刻的仓库列表
get_forked_repos() {
    log_info "获取您的复刻仓库列表..."
    
    local page=1
    local repos=""
    
    while true; do
        local response
        response=$(github_api "/user/repos?type=forks&sort=updated&per_page=100&page=$page")
        
        if [ "$(echo "$response" | jq length)" -eq 0 ]; then
            break
        fi
        
        repos="$repos$(echo "$response" | jq -r '.[] | select(.fork == true) | "\(.full_name)|\(.html_url)|\(.updated_at)"')"
        repos="$repos\n"
        
        page=$((page + 1))
    done
    
    if [ -z "$repos" ]; then
        log_error "未找到任何复刻仓库"
        exit 1
    fi
    
    echo "$repos" > "$REPO_CACHE_FILE"
    log_success "找到 $(echo "$repos" | grep -c '|') 个复刻仓库"
}

# 选择仓库
select_repository() {
    if [ ! -f "$REPO_CACHE_FILE" ]; then
        get_forked_repos
    fi
    
    local repos
    repos=$(cat "$REPO_CACHE_FILE")
    
    log_info "请选择要同步的仓库:"
    echo ""
    
    local i=1
    local repo_names=()
    local repo_urls=()
    
    while IFS='|' read -r full_name html_url updated_at; do
        if [ -n "$full_name" ]; then
            repo_names[i]="$full_name"
            repo_urls[i]="$html_url"
            echo -e "${CYAN}$i)${NC} $full_name (更新于: ${updated_at:0:10})"
            i=$((i + 1))
        fi
    done <<< "$repos"
    
    echo ""
    read -p "请输入仓库编号: " repo_choice
    
    if [ -z "${repo_names[repo_choice]}" ]; then
        log_error "无效的选择"
        exit 1
    fi
    
    SELECTED_REPO_NAME="${repo_names[repo_choice]}"
    SELECTED_REPO_URL="${repo_urls[repo_choice]}"
    
    log_success "已选择仓库: $SELECTED_REPO_NAME"
}

# 获取上游仓库信息
get_upstream_info() {
    log_info "获取上游仓库信息..."
    
    local response
    response=$(github_api "/repos/$SELECTED_REPO_NAME")
    
    UPSTREAM_REPO_FULL_NAME=$(echo "$response" | jq -r '.parent.full_name')
    UPSTREAM_REPO_URL=$(echo "$response" | jq -r '.parent.html_url')
    UPSTREAM_REPO_CLONE_URL=$(echo "$response" | jq -r '.parent.clone_url')
    
    if [ "$UPSTREAM_REPO_FULL_NAME" = "null" ]; then
        log_error "无法找到上游仓库信息"
        exit 1
    fi
    
    log_success "上游仓库: $UPSTREAM_REPO_FULL_NAME"
    log_info "上游URL: $UPSTREAM_REPO_CLONE_URL"
}

# 准备本地仓库
prepare_local_repo() {
    local repo_dir="./$(basename "$SELECTED_REPO_NAME")"
    
    if [ -d "$repo_dir" ]; then
        log_info "本地仓库已存在: $repo_dir"
        cd "$repo_dir"
        check_git_repo
    else
        log_info "克隆复刻仓库到本地..."
        git clone "$SELECTED_REPO_URL" "$repo_dir"
        cd "$repo_dir"
    fi
    
    # 添加上游远程仓库
    if git remote get-url upstream > /dev/null 2>&1; then
        log_info "上游远程仓库已配置"
        git remote set-url upstream "$UPSTREAM_REPO_CLONE_URL"
    else
        log_info "添加上游远程仓库"
        git remote add upstream "$UPSTREAM_REPO_CLONE_URL"
    fi
}

# 检查是否在git仓库中
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "当前目录不是Git仓库"
        exit 1
    fi
}

# 检查是否有未提交的更改
check_uncommitted_changes() {
    if ! git diff-index --quiet HEAD --; then
        log_warning "检测到未提交的更改"
        echo "请选择操作:"
        echo "1) 暂存更改 (推荐)"
        echo "2) 丢弃更改"
        echo "3) 退出脚本"
        read -p "请输入选择 (1/2/3): " choice
        
        case $choice in
            1)
                git add .
                git commit -m "备份本地更改: $(date '+%Y-%m-%d %H:%M:%S')"
                log_success "已暂存本地更改"
                ;;
            2)
                git reset --hard HEAD
                log_warning "已丢弃所有未提交的更改"
                ;;
            3)
                log_info "用户选择退出"
                exit 0
                ;;
            *)
                log_error "无效选择"
                exit 1
                ;;
        esac
    fi
}

# 获取当前分支
get_current_branch() {
    CURRENT_BRANCH=$(git branch --show-current)
    log_info "当前分支: $CURRENT_BRANCH"
}

# 主同步函数
sync_fork() {
    log_info "开始同步复刻仓库..."
    
    # 获取上游最新更改
    log_info "获取上游仓库更新..."
    git fetch upstream --tags --force
    
    # 备份当前分支（如果不是main/master）
    if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
        log_info "备份当前分支: $CURRENT_BRANCH"
        git branch -f "backup-$CURRENT_BRANCH-$(date '+%Y%m%d')" "$CURRENT_BRANCH"
    fi
    
    # 确定主分支名称
    if git show-ref --verify --quiet refs/heads/main; then
        MAIN_BRANCH="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        MAIN_BRANCH="master"
    else
        log_error "未找到main或master分支"
        exit 1
    fi
    
    log_info "使用主分支: $MAIN_BRANCH"
    
    # 切换到主分支
    if [ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]; then
        git checkout "$MAIN_BRANCH"
    fi
    
    # 重置到上游状态
    log_info "重置本地分支到上游状态..."
    git reset --hard "upstream/$MAIN_BRANCH"
    
    # 推送到origin
    log_info "推送到复刻仓库..."
    git push origin "$MAIN_BRANCH" --force
    
    log_success "同步完成!"
}

# 显示同步信息
show_sync_info() {
    log_info "同步统计:"
    echo "------------------------"
    
    # 获取一年前的日期
    local one_year_ago
    one_year_ago=$(date -d "1 year ago" +%Y-%m-%d 2>/dev/null || date -v-1y +%Y-%m-%d 2>/dev/null || echo "1 year ago")
    
    local commit_count
    commit_count=$(git log --oneline "upstream/$MAIN_BRANCH" --since="$one_year_ago" | wc -l)
    
    echo "过去一年的提交数量: $commit_count"
    echo "最新提交:"
    git log -1 --format="%h - %s (%cr)" "upstream/$MAIN_BRANCH"
    echo "------------------------"
}

# 清理函数
cleanup() {
    log_info "清理临时资源..."
    # 可以在这里添加清理代码
}

# 显示欢迎信息
show_welcome() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║           GitHub 复刻同步工具            ║"
    echo "║           GitHub Fork Sync Tool          ║"
    echo "║           作者：酷安@筱笙墨露            ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 显示使用说明
show_usage() {
    echo "使用方法:"
    echo "  $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -v, --version  显示版本信息"
    echo "  --clean        清理缓存和配置"
    echo ""
    echo "功能:"
    echo "  1. 自动检测并安装所需依赖"
    echo "  2. GitHub 认证和仓库列表获取"
    echo "  3. 选择要同步的复刻仓库"
    echo "  4. 自动同步上游所有提交记录"
    echo ""
}

# 清理缓存和配置
cleanup_config() {
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        log_success "已清理所有缓存和配置"
    else
        log_info "没有找到缓存配置"
    fi
}

# 显示版本信息
show_version() {
    echo "GitHub Fork Sync Tool v1.1.0"
    echo "支持自动依赖安装和完整复刻同步"
    echo "支持的操作系统: macOS, Windows, Linux (多种发行版), FreeBSD, OpenBSD"
}

# 参数解析
parse_arguments() {
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        --clean)
            cleanup_config
            exit 0
            ;;
        *)
            # 无参数或未知参数，继续执行主程序
            ;;
    esac
}

# 主函数
main() {
    parse_arguments "$@"
    show_welcome
    
    # 设置陷阱，确保脚本退出时执行清理
    trap cleanup EXIT
    
    # 初始化和依赖安装
    detect_os_and_pm
    install_dependencies
    create_config_dir
    
    # GitHub认证和仓库选择
    github_auth
    select_repository
    get_upstream_info
    
    # 准备本地仓库
    prepare_local_repo
    get_current_branch
    check_uncommitted_changes
    
    # 确认操作
    log_warning "此操作将用上游仓库的完整历史覆盖你的复刻仓库"
    log_warning "仓库: $SELECTED_REPO_NAME"
    log_warning "上游: $UPSTREAM_REPO_FULL_NAME"
    read -p "确定要继续吗? (y/N): " confirm
    case $confirm in
        [yY]|[yY][eE][sS])
            log_info "开始同步..."
            ;;
        *)
            log_info "用户取消操作"
            exit 0
            ;;
    esac
    
    # 执行同步
    sync_fork
    show_sync_info
    
    log_success "复刻同步完成!"
    log_info "本地仓库位置: $(pwd)"
}

# 运行主函数
main "$@"