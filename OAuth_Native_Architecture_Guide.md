# Kiến Trúc Tích Hợp Super App (Hybrid Ecosystem) & Giải Pháp Native SSO

Tài liệu này tổng hợp chiến lược kiến trúc để xây dựng Super App cốt lõi (TCCT) và hướng dẫn kỹ thuật triển khai luồng Single Sign-On (SSO) App-to-App hoàn toàn bằng Native, nhằm tích hợp các module vệ tinh (như Sổ tay Đảng viên - SĐTV) một cách tối ưu, an toàn và có khả năng mở rộng (Scale).

---

## 1. Chiến Lược Tích Hợp: Mô Hình Kiến Trúc Lai (Hybrid Ecosystem)

Đối mặt với bài toán tích hợp hàng loạt ứng dụng con vào Super App TCCT, chúng ta áp dụng mô hình **Kiến trúc Lai** để giữ sự linh hoạt (Flexibility) và tối ưu nguồn lực (Resources):

- **Core Built-in Modules:** Các tính năng cốt lõi (domain hẹp, sử dụng chung state/UI) do nội bộ phát triển được Nhúng Trực Tiếp (Monolithic Embedding) vào mạch chính yếu nhằm đảm bảo tốc độ chuyển trang tức thì (Zero-latency) và quản lý tập trung trên 1 tệp tin cài đặt.
- **Satellite / External Modules (VD: SĐTV):** Các ứng dụng do đối tác hoặc team độc lập phát triển, mang tính domain nghiệp vụ lớn -> Được tích hợp mượn quyền thông qua kiến trúc **Đa Ứng dụng Phân tán (Native App-to-App SSO)**.

### Sự Đánh Đổi (Trade-offs) và Giải Pháp Tại Thời Điểm Hiện Tại:

Thay vì nhúng toàn bộ source code của app SĐTV vào TCCT (phương pháp _Monolithic Package Embedding_ có thể gây phình to dung lượng cài đặt khổng lồ, làm nghẽn cổ chai thời gian Build/Release của toàn bộ hệ thống, và rủi ro sập dây chuyền nếu 1 module cấp thấp bị tràn RAM), việc phân tách ứng dụng và kết dính bằng Native SSO (SSO giữa các Native Apps rời) mang lại điểm tối ưu ("The Sweet Spot"):

1. **Decoupled (Độc lập phân tán):** Team SĐTV tự chủ quy trình dev/release. Rủi ro và lỗi code ở SĐTV được cô lập, không thể đánh sập hệ thống TCCT.
2. **Lean App Size:** Tránh hội chứng "Siêu ứng dụng rác". Người dùng chỉ lưu trữ và cấp dung lượng tải cho những app vệ tinh (module) mà họ thực sự có nhu cầu sử dụng.
3. **Seamless UX (SSO):** Dù xé nhỏ ứng dụng, nhưng Trải nghiệm lại liền mạch. Người dùng đăng nhập 1 lần duy nhất trên Host Provider TCCT. Khi vào app SĐTV, hệ điều hành tự động gọi ngầm sang TCCT và "mượn" phiên làm việc chớp nhoáng mà không cần nhập lại mật khẩu.

_(Lưu ý: Đích đến quy mô khổng lồ của tương lai có thể là kiến trúc "Mini-App Platform" như WeChat, Zalo... nhưng giải pháp Native SSO là bước **chuyển tiếp (Transitional State)** hoàn hảo nhất ngay lúc này. Nó không lãng phí hàng chục nghìn Man-hour đập đi xây lại nền tảng Framework nội bộ, và bảo lưu nguyên vẹn 100% sức mạnh xử lý phần cứng của chuẩn Native UI)._

---

## 2. Vấn Đề Của OAuth 2.0 Truyền Thống (Web-based Flow)

Các thư viện tiêu chuẩn như `flutter_appauth` thường sử dụng **Chrome Custom Tabs** (Android) hoặc **ASWebAuthenticationSession** (iOS) để mở trang đăng nhập.

- **Hạn chế 1 (Trải nghiệm tệ):** Người dùng đang ở trong App A, bị đẩy sang trình duyệt Web (dù là in-app browser).
- **Hạn chế 2 (Gián đoạn):** Thay vì được nhảy thẳng sang App B (nếu đã cài đặt), người dùng phải thao tác trên giao diện Web Browser, mất đi tính liền mạch của hệ sinh thái mobile.

=> **Mục tiêu:** Xoá bỏ hoàn toàn Browser, ép hệ điều hành chuyển hướng trực tiếp từ Native App A sang Native App B.

---

## 2. Giải Pháp: Ép Chuyển Hướng Native (OS Interception)

Để ép hệ điều hành không dùng Browser, chúng ta sử dụng `url_launcher` với cấu hình mức độ gắt gao nhất: `LaunchMode.externalNonBrowserApplication`.
Lúc này, HĐH Android sẽ đi tìm kiếm xem trong máy có App nào đang "cầm sổ đỏ" sở hữu đường link `https://bloomygardenshop.com/authorize` hay không.

Để làm được điều này, App B (Auth Provider) phải đăng ký danh tính bằng **App Links** (Android) / **Universal Links** (iOS).

- App B khai báo `<intent-filter>` chứa path `/authorize`.
- Hosting `bloomygardenshop.com` chứa file `assetlinks.json` xác thực mã SHA-256 của App B.

=> Khi bấm "Login" ở App A, HĐH lập tức gọi thẳng App B thức dậy!

---

## 3. Lỗ Hổng Custom Scheme Hijacking & Giải Pháp

Sau khi đăng nhập xong ở App B, App B cần ném mã `Authorization Code` về lại cho App A.

Dùng AppLink và Universal Link, hệ điều hành Android thấy đây là Verified Link, nó sẽ đem bảo vệ trong lồng kính và **bắn thẳng về App A**. Không một Malware nào có quyền xen vào giữa luồng này.

---

## 4. Bảo Vệ App Lifecycle Memory Bằng Secure Storage

App trên Mobile có vòng đời (Lifecycle) rất phức tạp. Khi hệ điều hành nhảy từ App A -> App B, **Hệ điều hành có quyền dọn dẹp RAM của App A** đang nằm trong nền để tiết kiệm bộ nhớ.

### Thuật toán PKCE (Proof Key for Code Exchange)

Để chống lại việc Hacker đánh cắp Code, App A tự sinh ra một mã bí mật gọi là `code_verifier`.

- App A băm nhỏ nó ra thành `code_challenge`, gửi lên cho App B.
- Khi App B trả `code` về, App A phải đem cái chữ ký gốc `code_verifier` gửi thẳng lên Backend để chứng minh mình chính là người phát lệnh ban đầu.

### Triển khai Code (Best Practice)

Nếu App A lưu `code_verifier` trong RAM bằng các biến thông thường `String? currentCodeVerifier`:
=> Khi nhảy về từ App B, App A khởi động lại -> RAM bị xoá -> Biến là `null` -> LỖI NHẬP TRẠCH KHÔNG THỂ XÁC MINH CÚ PHÁP (`Invalid State! Expected null`).

**Giải Pháp:** Triển khai lưu trữ mã hoá vật lý trong Ổ cứng!
Sử dụng gói `flutter_secure_storage` (Tiêu chuẩn AES-CBC và Keychain):

1. Trước khi nhảy đi: Lưu `code_verifier` và `state` xuống Ổ cứng mã hoá.
2. Khi bị gọi vòng về bằng Deep Link: Moi từ Ổ cứng lên để đối chiếu.
3. Verify xong xoá rác khỏi ổ cứng: `storage.delete()`.

---

## 5. Kiến Trúc Backend Proxy Giấu Secret Key

App A đang ở ngoài Internet (Public Client). Nó KHÔNG ĐƯỢC PHÉP giữ `client_secret` của hệ thống Keycloak. Nếu nhét secret vào Mobile App mổ apk rra là mất mạng.

Do đó, bắt buộc phải có hệ thống **Backend Proxy Server**.

- App A chỉ đóng gói `code` (Lấy từ App B) và chữ ký `code_verifier` (PKCE) gửi cho Proxy (Cục C).
- Proxy Server (Cục C) đang nằm an toàn ở Server kín, sẽ tự trích xuất thư viện `client_secret` siêu bảo mật, đơm tài khoản Password Grant Type (nếu dùng chung Backend uỷ quyền) và liên hệ đến Keycloak (Cục D) để lấy `access_token` xịn về.
- Nhận token từ Keycloak, C trả ngược về cho A.

---

## TỔNG KẾT LUỒNG DỮ LIỆU HOÀN HẢO

1. **User ở App A:** Bấm "Login".
2. **App A (Native):** Sinh `code_verifier`, mã hoá thành `code_challenge`, sinh chuỗi ngẫu nhiên `state`. Lưu `verifier` + `state` vào **Secure Storage**.
3. **App A gọi URL:** deep link.
4. **Hệ Điều Hành HĐH:** Thấy App Link Verified! Xé rào không thông qua Chrome, bắn thẳng User đánh thức **App B**.
5. **App B (Native):** Thực hiện login, lấy được Token/Code nội bộ của nó. App B nhồi một mã uỷ quyền (Auth Code) cùng với cái `state` cũ vào URL callback.
6. **App B gọi URL:** deep link callback.
7. **HĐH HĐH:** Thấy App Link Verified! Chặn không cho ngõ ngách, ép mở lại **App A**.
8. **App A (Thức dậy):** Móc từ ổ cứng `Secure Storage` cái `state` cũ ra soi -> Trùng khớp! Ngăn chặn tấn công CSRF.
9. **App A:** Moi tiếp cái `code_verifier` đem gửi kèm cái Auth Code lên **Backend Proxy**.
10. **Backend Proxy:** Dùng Secret Key đổi lấy Access Token của hệ thống lõi **Keycloak** và trả về App A.
11. **App A:** Giao diện bừng sáng màu xanh, "Login Success"! Toàn bộ chu trình Native, không 1 khung web, khép kín hoàn toàn.
