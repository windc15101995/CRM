# Hạnh Nguyện · Học tập và Lan tỏa

Website Next.js cho đăng ký Zoom **1h viết lại tương lai**, lớp **Thực tập tư duy làm chủ 6 ngày**, Hạnh Nguyện, phước đức và CRM theo cây lan tỏa.

## Chạy và kiểm tra

```sh
npm ci
npm run dev
npm run build
npm run typecheck
node scripts/verify-system.mjs
```

## Triển khai trên Vercel

- Framework: Next.js.
- Node.js: 22.x hoặc mới hơn.
- Install: `npm ci`; Build: `npm run build`.
- Cấu hình `HN_SUPABASE_URL` và `HN_SUPABASE_KEY` tại Vercel Project Settings > Environment Variables cho Production và Preview.
- `HN_SUPABASE_KEY` là publishable API key của Supabase. Không dùng service-role key.
- Không đưa khóa, mật khẩu quản trị, phiên đăng nhập hoặc dữ liệu học viên vào GitHub.
- Dự án Vercel kết nối với nhánh `main` để cập nhật khi có commit mới.

## Cơ sở dữ liệu đang dùng

Website dùng chung Supabase với bản Sites. Không chạy lại schema hoặc nhập lại dữ liệu khi chuyển hosting.

Schema riêng: `hn`. RPC: `public.hn_request`. URL/khóa chỉ đọc ở máy chủ qua biến môi trường; cookie phiên đăng nhập HttpOnly và Secure.

Các file `supabase/schema.sql` và `supabase/operations.sql` là mã nguồn cấu trúc và nghiệp vụ để đối chiếu. Không tự chạy trên database đang hoạt động. `supabase/verify.sql` kiểm tra nghiệp vụ trong giao dịch rồi ROLLBACK, nhận mật khẩu quản trị qua cấu hình giao dịch `hn.test_admin_password`.

## Tài khoản và phân quyền

- Học viên/Trợ lực: user là số điện thoại; mật khẩu ban đầu `123456`; có mục đổi mật khẩu.
- User quản trị hệ thống: `adminsss`; mật khẩu đã được cấu hình trong Supabase theo yêu cầu chủ sở hữu.
- Mã giới thiệu 5 ký tự ngẫu nhiên và duy nhất, tách biệt mật khẩu.
- Tài khoản mới là Học viên; chỉ admin phê duyệt Trợ lực.
- Học viên chỉ xem tên người trực tiếp giới thiệu.
- Trợ lực xử lý CRM và xem toàn bộ các tầng trong nhánh được giao.
- Giao/điều chuyển một học viên là giao cả cây phía dưới. Người mới kế thừa Trợ lực của nhánh. Trợ lực cũ mất quyền xem phần đã chuyển.

## Quyền lợi

- Xác nhận thực tế học Zoom 1h: +1/180 và một lượt quyền học cho người giới thiệu trực tiếp, không cộng trùng.
- Người được giới thiệu vào chương trình 6 ngày được xác nhận: +200.000đ phước đức cho người giới thiệu trực tiếp, một lần.
- Đóng 600.000đ được xác nhận hoặc tích lũy đủ 600.000đ phước đức: đủ điều kiện được duyệt MTD. Tổng phước đức giữ nguyên; phần vượt tiếp tục hiển thị.
- Quyền lợi không tự cộng từ các tầng sâu lên nhiều tầng.
