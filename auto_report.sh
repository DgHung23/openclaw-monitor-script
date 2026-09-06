#!/bin/bash

# ============================================================
# Linux Health Report
# Designed for remote execution via SSH / OpenClaw
# ============================================================

HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Thresholds
CPU_WARN=80
CPU_CRIT=95

RAM_WARN=80
RAM_CRIT=90

DISK_WARN=80
DISK_CRIT=90

LOAD_WARN=$(nproc)
LOAD_CRIT=$(( $(nproc) * 2 ))

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

status_icon() {
    case "$1" in
        OK)       echo "🟢" ;;
        WARNING)  echo "🟡" ;;
        CRITICAL) echo "🔴" ;;
        *)        echo "🔹" ;;
    esac
}

get_status() {
    local value=$1
    local warn=$2
    local crit=$3

    if (( value >= crit )); then
        echo "CRITICAL"
    elif (( value >= warn )); then
        echo "WARNING"
    else
        echo "OK"
    fi
}

# ------------------------------------------------------------
# Data Collection
# ------------------------------------------------------------

# Basic info
KERNEL=$(uname -r)
OS_NAME=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')
OS_NAME=${OS_NAME:-$(uname -s)}
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'( |,|:)+' '{d=h=m=0; print $0}')

# Network
DEFAULT_INTERFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
if [[ -n "$DEFAULT_INTERFACE" ]]; then
    IP_ADDRESS=$(ip -4 addr show "$DEFAULT_INTERFACE" 2>/dev/null | awk '/inet / {print $2; exit}')
    NET_INFO="$DEFAULT_INTERFACE ($IP_ADDRESS)"
else
    NET_INFO="Không tìm thấy interface mặc định"
fi

# CPU
CPU_USAGE=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/ {print 100 - $8}' | cut -d. -f1)
if [[ -z "$CPU_USAGE" ]]; then
    CPU_USAGE=$(mpstat 1 1 2>/dev/null | awk '/Average:/ {print 100 - $NF}' | cut -d. -f1)
fi
CPU_USAGE=${CPU_USAGE:-0}
CPU_STATUS=$(get_status "$CPU_USAGE" "$CPU_WARN" "$CPU_CRIT")
CPU_CORES=$(nproc)
LOAD_AVG=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null)

# RAM
read -r TOTAL_RAM USED_RAM FREE_RAM <<< \
$(free -m | awk '/Mem:/ {print $2, $3, $4}')
TOTAL_RAM=${TOTAL_RAM:-1}
USED_RAM=${USED_RAM:-0}
FREE_RAM=${FREE_RAM:-0}
RAM_USAGE=$(( USED_RAM * 100 / TOTAL_RAM ))
RAM_STATUS=$(get_status "$RAM_USAGE" "$RAM_WARN" "$RAM_CRIT")

# System Load status
LOAD_1=$(awk '{print int($1)}' /proc/loadavg 2>/dev/null || echo 0)
if (( LOAD_1 >= LOAD_CRIT )); then
    LOAD_STATUS="CRITICAL"
elif (( LOAD_1 >= LOAD_WARN )); then
    LOAD_STATUS="WARNING"
else
    LOAD_STATUS="OK"
fi

# Disk
DISK_STATUS="OK"
DISK_REPORT=""
while read -r filesystem size used avail percent mountpoint; do
    usage=${percent%\%}
    if (( usage >= DISK_CRIT )); then
        current_status="CRITICAL"
    elif (( usage >= DISK_WARN )); then
        current_status="WARNING"
    else
        current_status="OK"
    fi

    DISK_REPORT+="$(printf "%s %s: %s (%s/%s)\n" "$(status_icon "$current_status")" "$mountpoint" "$percent" "$used" "$size")"
    DISK_REPORT+=$'\n'

    if [[ "$current_status" == "CRITICAL" ]]; then
        DISK_STATUS="CRITICAL"
    elif [[ "$current_status" == "WARNING" && "$DISK_STATUS" == "OK" ]]; then
        DISK_STATUS="WARNING"
    fi
done < <(
    df -hP -x tmpfs -x devtmpfs 2>/dev/null |
    tail -n +2 |
    awk '{print $1,$2,$3,$4,$5,$6}'
)
DISK_REPORT=$(echo "$DISK_REPORT" | sed '/^$/d')

# Failed systemd services
FAILED_SERVICES=$(systemctl --failed --no-legend --no-pager 2>/dev/null | awk '{print $2}' | tr '\n' ', ' | sed 's/,$//')

# Zombie processes
ZOMBIES=$(ps -eo stat= 2>/dev/null | grep -c 'Z')

# SSH status
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    SSH_STATUS="OK"
else
    SSH_STATUS="WARNING"
fi

# Inodes check
INODE_STATUS="OK"
INODE_ALERT=""
while read -r filesystem inodes iused ifree percent mountpoint; do
    usage=${percent%\%}
    if (( usage >= 90 )); then
        INODE_STATUS="CRITICAL"
        INODE_ALERT+="🔴 $mountpoint: $percent | "
    elif (( usage >= 80 )); then
        if [[ "$INODE_STATUS" == "OK" ]]; then INODE_STATUS="WARNING"; fi
        INODE_ALERT+="🟡 $mountpoint: $percent | "
    fi
done < <(
    df -iP -x tmpfs -x devtmpfs 2>/dev/null |
    tail -n +2 |
    awk '{print $1,$2,$3,$4,$5,$6}'
)
INODE_ALERT=${INODE_ALERT% | }

# Recent errors (last 10 mins)
ERROR_COUNT=$(journalctl -p err -S "-10 min" --no-pager -q 2>/dev/null | wc -l)

# Calculate Overall Status
OVERALL="OK"
for s in "$CPU_STATUS" "$RAM_STATUS" "$DISK_STATUS" "$LOAD_STATUS" "$INODE_STATUS"; do
    if [[ "$s" == "CRITICAL" ]]; then
        OVERALL="CRITICAL"
        break
    elif [[ "$s" == "WARNING" && "$OVERALL" == "OK" ]]; then
        OVERALL="WARNING"
    fi
done

# ------------------------------------------------------------
# Presentation formatted for Zalo Messaging
# ------------------------------------------------------------

echo "📊 [BÁO CÁO HỆ THỐNG LINUX]"
echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo "$(status_icon "$OVERALL") TRẠNG THÁI: $OVERALL"
echo "🖥️ Host: $HOSTNAME"
echo "🌐 IP: $NET_INFO"
echo "⏱️ Uptime: $UPTIME"
echo "🕒 Thời gian: $TIMESTAMP"
echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "⚡ HIỆU NĂNG PHẦN CỨNG"
echo "$(status_icon "$CPU_STATUS") CPU: ${CPU_USAGE}% (${CPU_CORES} cores)"
echo "$(status_icon "$LOAD_STATUS") Load Avg: $LOAD_AVG"
echo "$(status_icon "$RAM_STATUS") RAM: ${RAM_USAGE}% (${USED_RAM}MB / ${TOTAL_RAM}MB)"
echo ""

echo "💽 DUNG LƯỢNG Ổ CỨNG"
if [[ -n "$DISK_REPORT" ]]; then
    echo "$DISK_REPORT"
else
    echo "🟢 Bình thường"
fi
if [[ -n "$INODE_ALERT" ]]; then
    echo "⚠️ Inode cao: $INODE_ALERT"
fi
echo ""

echo "⚙️ TRẠNG THÁI DỊCH VỤ"
if [[ "$SSH_STATUS" == "OK" ]]; then
    echo "🟢 SSH Service: Đang chạy"
else
    echo "🔴 SSH Service: ĐÃ DỪNG"
fi

if [[ -z "$FAILED_SERVICES" ]]; then
    echo "🟢 Systemd Service: Hoạt động tốt"
else
    echo "🔴 Systemd lỗi: $FAILED_SERVICES"
fi

if (( ZOMBIES > 0 )); then
    echo "🟡 Zombie Process: $ZOMBIES process"
else
    echo "🟢 Zombie Process: 0"
fi

if (( ERROR_COUNT > 0 )); then
    echo "🟡 Log lỗi (10m): $ERROR_COUNT lỗi ghi nhận"
else
    echo "🟢 Log lỗi (10m): 0 lỗi"
fi
echo ""

echo "🔥 TOP TIẾN TRÌNH CHIẾM TÀI NGUYÊN"
echo "▶ Top CPU:"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=4 {printf " • %s (PID %s): %s%% CPU, %s%% RAM\n", $2, $1, $3, $4}'

echo "▶ Top RAM:"
ps -eo pid,comm,%cpu,%mem --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=4 {printf " • %s (PID %s): %s%% RAM, %s%% CPU\n", $2, $1, $4, $3}'

echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo "🤖 Auto Report by OpenClaw Monitor"

# Exit Code làm cờ (Flag) cho OpenClaw / Automation script
case "$OVERALL" in
    CRITICAL) exit 2 ;;
    WARNING)  exit 1 ;;
    *)        exit 0 ;;
esac