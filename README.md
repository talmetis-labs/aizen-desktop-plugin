<div align="center">

# Aizen Desktop

**Lớp giao diện desktop cho [aizen](https://github.com/aizen-stack/aizen) — Tauri v2 · Svelte 5 · không Electron.**

</div>

---

Aizen Desktop là cửa sổ đồ hoạ cho `aizen` coding agent: cây tệp, editor, diff theo hunk, memory
brain, persona, MCP, giao việc song song nhiều agent. Nó **không đóng gói engine** — app đi tìm
binary `aizen` bạn đã cài và dùng chính nó.

> Đây là repo **phân phối**: chỉ chứa trình cài và các bản phát hành (Releases). Mã nguồn không nằm ở đây.

## Cài

Gói cài có bản quyền: **trình cài xác nhận tài khoản đã mua rồi mới tải**. Chưa có gói thì mua tại
[aizen.sh](https://aizen.sh).

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/talmetis-labs/aizen-desktop-plugin/main/install.ps1 | iex
```

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/talmetis-labs/aizen-desktop-plugin/main/install.sh | sh
```

Trình cài mở trình duyệt để bạn xác nhận mua hàng (device-code), sau đó tải **một file** đặt cạnh
`aizen`, kích hoạt sẵn licence trên máy, và tạo shortcut. Không toolchain, không Node, không Rust.

### Yêu cầu

- **`aizen` CLI** — engine mà app điều khiển. Cài trước: `irm https://raw.githubusercontent.com/aizen-stack/aizen/main/install.ps1 | iex` (Windows) hoặc bản `install.sh` tương ứng.
- **Windows:** WebView2 Evergreen Runtime (có sẵn trên Windows 11 và mọi máy có Edge).
- **Linux:** `libwebkit2gtk-4.1`.
- **macOS:** Apple Silicon (arm64).

## Cập nhật & gỡ

App tự kiểm bản mới từ trang Releases của repo này. Gỡ: xoá `aizen-desktop.exe` (Windows, trong
`%LOCALAPPDATA%\Aizen`) hoặc `~/.aizen/bin/aizen-desktop` (Linux/macOS) và shortcut tương ứng.

## Bản quyền

Xem [LICENSE](LICENSE). Quyền sử dụng gói cài gắn với tài khoản đã mua; quản lý gói tại
[aizen.sh](https://aizen.sh).
