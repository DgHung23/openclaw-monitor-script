# 🚀 OpenClaw Monitor Script

Hệ thống giám sát trạng thái sức khỏe máy chủ Linux và tự động gửi báo cáo định kỳ qua Zalo thông qua **OpenClaw**.

---

## 📌 Kiến trúc hệ thống
- **OpenClaw Host**: Máy chủ điều khiển, định kỳ mỗi 10 phút SSH sang các máy con (Target VM) để thực thi script lấy báo cáo và gửi thông báo Zalo cho 3 Admin.
- **Target VM (Máy được giám sát)**: Máy chủ Linux chạy script `setup.sh` để cấp quyền, tạo user SSH và đặt file `auto_report.sh` vào hệ thống.

---

## 🛠️ Hướng dẫn cài đặt trên Target VM (Máy cần giám sát)

Chỉ cần thực hiện 2 bước đơn giản trên máy cần monitor:

```bash
# 1. Clone repository về máy
git clone https://github.com/DgHung23/openclaw-monitor-script.git
cd openclaw-monitor-script

# 2. Chạy script cài đặt tự động với quyền root/sudo
sudo bash setup.sh
```

### Script `setup.sh` sẽ tự động thực hiện:
1. **Triển khai `auto_report.sh`**: Sao chép vào `/usr/local/bin/auto_report.sh` và cấp quyền thực thi `755`.
2. **Tạo User `openclaw`**: Tạo user chuyên dụng với quyền tối thiểu an toàn, thêm vào nhóm `systemd-journal, adm` để xem log mà không cần cấp full sudo/root.
3. **Thiết lập SSH Credentials**: Tự động sinh cặp SSH Key (Ed25519/RSA), cấu hình `authorized_keys`, lưu file private key và tạo mật khẩu an toàn dự phòng.
4. **Xuất cấu hình**: In toàn bộ thông tin kết nối (IP, Port, User, Password, Private Key, Lệnh thực thi) ngay trên màn hình.

---

## 🤖 Cấu hình trên OpenClaw Host

Sau khi chạy `setup.sh`, copy file private key hoặc chuỗi key sang OpenClaw Host.

### 1. Test kết nối thủ công từ OpenClaw Host:
```bash
ssh -i openclaw_id_ed25519 -p <PORT> openclaw@<TARGET_IP> /usr/local/bin/auto_report.sh
```

### 2. Ra lệnh cho OpenClaw bằng ngôn ngữ tự nhiên:
> *"Cứ mỗi 10 phút một lần, hãy SSH vào máy `<TARGET_IP>` (user: `openclaw`, port: `<PORT>`, dùng SSH key) và chạy lệnh `/usr/local/bin/auto_report.sh`. Lấy toàn bộ kết quả output trả về và gửi tin nhắn thông báo qua Zalo cho 3 admin: [SĐT_Admin_1], [SĐT_Admin_2], [SĐT_Admin_3]."*

---

## 📊 Định dạng báo cáo Zalo
Báo cáo được tối ưu giao diện gọn gàng, sử dụng emoji trạng thái trực quan, không bị vỡ giao diện trên mobile:
- 🟢/🟡/🔴 **Trạng thái tổng quan** ở ngay đầu báo cáo.
- ⚡ **Tài nguyên**: CPU, Cores, Load Average, RAM usage.
- 💽 **Ổ cứng**: Mountpoint, dung lượng sử dụng, cảnh báo Inode.
- ⚙️ **Dịch vụ**: SSH, Systemd, Zombie processes, System error logs.
- 🔥 **Top tiến trình** ngốn CPU và RAM nhất.
