# 🛡️ App-to-App OAuth 2.0 (SSO) Demo

Một hệ thống nguyên mẫu (Proof of Concept) trình diễn **Kiến trúc Tích hợp Lai (Hybrid Architecture)** cho các Siêu ứng dụng (Super App), tập trung vào giải pháp tái sử dụng phiên đăng nhập thông qua **Native App-to-App SSO** (Single Sign-On giữa các ứng dụng Native rời rạc) với **OAuth 2.0 + PKCE**.

Dự án mô phỏng kịch bản:

- Ứng dụng trung tâm **Auth Provider App** đóng vai trò là xương sống định danh.
- Ứng dụng vệ tinh **Client App** mượn phiên đăng nhập của Auth Provider App một cách mượt mà, không yêu cầu người dùng phải gõ lại Mật khẩu, cũng không bị đẩy ra Trình duyệt Web (Zero-Browser).

---

## 🌟 Kiến Trúc Hệ Thống (4-Component Architecture)

Hệ thống hoạt động dựa trên 4 trụ cột tương tác khép kín:

1. **📱 Auth Provider App (Nhặt Link & Cấp Quyền)**
   - Ngồi ngay cửa ngõ thiết bị HĐH (Android/iOS).
   - Nếu User chưa login, bắt Login. Nếu Login rồi, hiển thị mượt mà **Consent Dialog (Popup xin quyền)**.
   - Giao tiếp bảo mật với Backend để báo cáo uỷ quyền.

2. **📱 Client App (Người xin quyền)**
   - Tự sinh hệ thống khóa **PKCE (Challenge & Verifier)** và mã ngẫu nhiên **State** (Chống CSRF) lưu vào ổ cứng siêu bảo mật `Secure Storage`.
   - Dùng OS Deep Link gọi cửa Auth Provider App.
   - Khi nhận được tín hiệu trả về, đổi Code lấy Access Token.

3. **⚙️ Backend Proxy (BFF - Kẻ Thế Thân Giữ Chìa Khóa)**
   - Đóng vai trò Backend For Frontend. App Mobile sẽ không giao tiếp trực tiếp với Keycloak.
   - Cầm `Client Secret` siêu bảo mật, giấu trong lòng giếng sâu (Server-side).
   - Tự sinh `Auth Code` mồi nhử cấp về cho Mobile, giấu Access Token thật sự vào RAM Cache.

4. **🔐 Keycloak IDP (Identity Provider Cốt Lõi)**
   - Trạm bảo vệ chốt rốt. Chỉ cấp Token thật khi được Backend Proxy xác nhận bằng API (Server-to-Server).

---

## 🚀 Tính Năng Bảo Mật Vượt Trội (Zero-Trust)

- **OS-Level Verified App Links:** Chống triệt để chiêu trò Hacker cài Malware làm nhái link để "Cướp sóng" (Link Hijacking).
- **Phép Màu vòng lặp PKCE:** Client App đẻ mã Challenge đi gửi cho Auth Provider App, giấu mã Verifier ở nhà. Chỉ khi trùng mã Verifier mới đổi được Token. Auth Code nhỡ có bị cướp giữa đường cũng là rác.
- **BFF Pattern & RAM Cache:** Tuyệt đối không để `Client Secret` và `Access Token` thật bay phấp phới qua không khí ở bước nhảy từ Auth Provider App về Client App.

---

## 💻 Hướng Dẫn Kích Hoạt (Chạy Local)

Hệ thống cần chạy đồng bộ 4 Terminal để giả lập toàn bộ hệ sinh thái.

### Bước 1: Khởi động Lõi Keycloak (Cổng 8080)

Cần có Docker cài sẵn.

```bash
./setup_keycloak.sh
```

_(Đợi Keycloak khởi động xong, màn hình báo Admin Console is running...)_

### Bước 2: Khởi động Backend Proxy (Cổng 8081)

```bash
python3 backend_server.py
```

_(Đây là cục BFF kết nối ngầm với Keycloak ở bước 1)._

### Bước 3: Build & Chạy Auth Provider App

Mở một Terminal mới (Hoặc mở bằng Android Studio), kết nối Máy ảo / Điện thoại thật:

```bash
cd auth_provider_app
flutter run
```

_Lưu ý: Bạn phải cài đặt App này vào máy ảo trước để hệ điều hành nhận diện được Deep Link._

### Bước 4: Build & Chạy Client App

Mở một Terminal cuối cùng:

```bash
cd client_app
flutter run
```

---

## 🧪 Kịch Bản Test Khuyên Dùng

Đảm bảo hai App **Auth Provider** và **Client** đều đã nằm sẵn trên máy bạn.

1. Mở **Auth Provider App**, đăng nhập bằng tài khoản giả lập: Nhập bừa User/Pass -> Bấm Login. App sẽ báo bừng sáng báo thành công và có chữ **Logged in as...**. Thoát ra màn hình trang chủ.
2. Mở **Client App**, bấm nút **"Login with Auth Provider App"**.
3. **Sự kỳ diệu:** Hệ điều hành chớp nhoáng kéo Auth Provider App lên mặt tiền. Auth Provider App **KHÔNG** bắt log in lại, mà nổi lên popup: _"Ứng dụng Client muốn xin quyền... Đồng Ý / Từ Chối"_.
4. Bấm **"Đồng ý"**, HĐH giật chớp nhoáng kéo bản thân bạn trở về Client App.
5. Xem log terminal: Mã Token thực sự đã chảy vào tay Client App. Đăng nhập mượt mà!

---

