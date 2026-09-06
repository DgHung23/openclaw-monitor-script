#!/bin/bash
# ==============================================================================
# OpenClaw Monitor - Target VM Provisioning Script
# Tự động khởi tạo user, cấp SSH credential và triển khai auto_report.sh
# ==============================================================================

set -e

# Màu sắc terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Script này phải được chạy với quyền root hoặc sudo!${NC}"
    echo "Ví dụ: sudo bash setup.sh"
    exit 1
fi

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          OPENCLAW MONITOR - SETUP TARGET VM                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/auto_report.sh"
TARGET_DIR="/usr/local/bin"
TARGET_SCRIPT="$TARGET_DIR/auto_report.sh"
MONITOR_USER="openclaw"
PRIVATE_KEY_BACKUP="/root/openclaw_id_ed25519"
LOCAL_KEY_BACKUP="$SCRIPT_DIR/openclaw_id_ed25519"

# ------------------------------------------------------------------------------
# 1. Cài đặt file auto_report.sh vào hệ thống
# ------------------------------------------------------------------------------
echo -e "${BLUE}[1/5] Đang triển khai auto_report.sh vào hệ thống...${NC}"

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
    echo -e "${RED}[ERROR] Không tìm thấy file auto_report.sh trong thư mục: $SCRIPT_DIR${NC}"
    exit 1
fi

mkdir -p "$TARGET_DIR"
cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
chmod 755 "$TARGET_SCRIPT"
chown root:root "$TARGET_SCRIPT"

echo -e "${GREEN}  ✓ Đã copy script vào: $TARGET_SCRIPT (quyền 755)${NC}"

# ------------------------------------------------------------------------------
# 2. Tạo dedicated user cho OpenClaw
# ------------------------------------------------------------------------------
echo -e "${BLUE}[2/5] Đang cấu hình user cho OpenClaw ($MONITOR_USER)...${NC}"

if id "$MONITOR_USER" &>/dev/null; then
    echo -e "${YELLOW}  ! User '$MONITOR_USER' đã tồn tại, tiến hành cập nhật quyền.${NC}"
else
    useradd -m -s /bin/bash "$MONITOR_USER"
    echo -e "${GREEN}  ✓ Đã tạo mới user: $MONITOR_USER${NC}"
fi

# Thêm user vào group đọc logs hệ thống mà không cần sudo
usermod -aG systemd-journal,adm "$MONITOR_USER" 2>/dev/null || true
echo -e "${GREEN}  ✓ Đã cấp quyền đọc nhật ký hệ thống (systemd-journal, adm)${NC}"

# Tạo mật khẩu ngẫu nhiên an toàn (16 ký tự)
USER_PASS=$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom 2>/dev/null | head -c 16 || openssl rand -base64 12)
echo "$MONITOR_USER:$USER_PASS" | chpasswd
echo -e "${GREEN}  ✓ Đã thiết lập mật khẩu cho user $MONITOR_USER${NC}"

# ------------------------------------------------------------------------------
# 3. Cấu hình SSH Authorized Keys (Hỗ trợ Public Key từ OpenClaw)
# ------------------------------------------------------------------------------
echo -e "${BLUE}[3/5] Đang cấu hình SSH Keys cho OpenClaw...${NC}"

USER_HOME=$(eval echo "~$MONITOR_USER")
SSH_DIR="$USER_HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Kiểm tra nếu người dùng truyền Public Key từ OpenClaw qua tham số ($1) hoặc biến môi trường
OPENCLAW_PUBKEY="${1:-$OPENCLAW_PUBKEY}"

if [[ -n "$OPENCLAW_PUBKEY" ]]; then
    echo "$OPENCLAW_PUBKEY" >> "$SSH_DIR/authorized_keys"
    echo -e "${GREEN}  ✓ Đã nạp Public Key của OpenClaw Host vào authorized_keys!${NC}"
fi

# Tự động sinh thêm 1 cặp Local Key dự phòng
TEMP_KEY=$(mktemp -u /tmp/openclaw_key_XXXXXX)
if ! ssh-keygen -t ed25519 -N "" -f "$TEMP_KEY" -C "openclaw-monitor-$(hostname)" -q 2>/dev/null; then
    ssh-keygen -t rsa -b 4096 -N "" -f "$TEMP_KEY" -C "openclaw-monitor-$(hostname)" -q
fi

cat "${TEMP_KEY}.pub" >> "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"
chown -R "$MONITOR_USER:$MONITOR_USER" "$SSH_DIR"

cp "$TEMP_KEY" "$PRIVATE_KEY_BACKUP"
chmod 600 "$PRIVATE_KEY_BACKUP"
cp "$TEMP_KEY" "$LOCAL_KEY_BACKUP"
chmod 600 "$LOCAL_KEY_BACKUP"

PRIVATE_KEY_CONTENT=$(cat "$TEMP_KEY")
rm -f "$TEMP_KEY" "${TEMP_KEY}.pub"

echo -e "${GREEN}  ✓ Đã cấu hình hoàn tất SSH Authorized Keys cho $MONITOR_USER${NC}"

# ------------------------------------------------------------------------------
# 4. Kiểm tra dịch vụ SSH
# ------------------------------------------------------------------------------
echo -e "${BLUE}[4/5] Đang kiểm tra dịch vụ SSH...${NC}"

# Kích hoạt SSH service nếu chưa bật
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true

# Lấy cổng SSH đang lắng nghe (mặc định 22)
SSH_PORT=$(ss -tlpn 2>/dev/null | awk '/sshd/ {print $4}' | awk -F: '{print $NF}' | sort -u | head -n1)
SSH_PORT=${SSH_PORT:-22}

# Lấy địa chỉ IP chính của máy
TARGET_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
if [[ -z "$TARGET_IP" ]]; then
    TARGET_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
TARGET_IP=${TARGET_IP:-"127.0.0.1"}

echo -e "${GREEN}  ✓ SSH Service đang hoạt động trên Port: $SSH_PORT${NC}"
echo -e "${GREEN}  ✓ IP của máy: $TARGET_IP${NC}"

# ------------------------------------------------------------------------------
# 5. Xuất thông tin cấu hình cho OpenClaw
# ------------------------------------------------------------------------------
echo -e "${BLUE}[5/5] Hoàn tất thiết lập! Xuất thông số cấu hình OpenClaw...${NC}"
echo ""

echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW}${BOLD}     THÔNG TIN CẤU HÌNH DÀNH CHO HOST OPENCLAW${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${BOLD}1. THÔNG TIN KẾT NỐI SSH:${NC}"
echo -e "   • Target Host (IP) : ${GREEN}${BOLD}$TARGET_IP${NC}"
echo -e "   • SSH Port         : ${GREEN}${BOLD}$SSH_PORT${NC}"
echo -e "   • SSH User         : ${GREEN}${BOLD}$MONITOR_USER${NC}"
echo -e "   • SSH Password     : ${GREEN}${BOLD}$USER_PASS${NC}"
echo -e "   • Remote Command   : ${GREEN}${BOLD}$TARGET_SCRIPT${NC}"
echo -e "   • File Private Key : ${GREEN}$LOCAL_KEY_BACKUP${NC} (hoặc $PRIVATE_KEY_BACKUP)"
echo ""
echo -e "${BOLD}2. LỆNH TEST SSH TỪ OPENCLAW HOST:${NC}"
echo -e "   ${CYAN}ssh -i openclaw_id_ed25519 -p $SSH_PORT $MONITOR_USER@$TARGET_IP $TARGET_SCRIPT${NC}"
echo ""
echo -e "${BOLD}3. NỘI DUNG SSH PRIVATE KEY (Copy nguyên block bên dưới vào OpenClaw):${NC}"
echo -e "${YELLOW}-------------------------- BẮT ĐẦU KEY --------------------------${NC}"
echo "$PRIVATE_KEY_CONTENT"
echo -e "${YELLOW}-------------------------- KẾT THÚC KEY -------------------------${NC}"
echo ""
echo -e "${BOLD}4. GỢI Ý PROMPT RA LỆNH CHO OPENCLAW (Ngôn ngữ tự nhiên):${NC}"
echo -e "${CYAN}\"Cứ mỗi 10 phút một lần, hãy SSH vào máy $TARGET_IP (user: $MONITOR_USER, port: $SSH_PORT, sử dụng SSH key) và chạy lệnh '$TARGET_SCRIPT'. Lấy kết quả output trả về và gửi tin nhắn thông báo qua Zalo cho 3 admin: [SĐT_Admin_1], [SĐT_Admin_2], [SĐT_Admin_3].\"${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}${BOLD}✓ Cài đặt hoàn tất thành công!${NC}"
