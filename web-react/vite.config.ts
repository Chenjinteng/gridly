import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Vite dev server 配置
//
// LAN_WEB P4 mock server 模式(2026-10-17 加):
// - /api/* 请求转发到 mock_server (http://localhost:8123),
//   让 web-react 独立于 Flutter app 跑,不用每次启 macOS dev。
// - mock_server 默认配对码 "123456",启动时自带 1 个 active session,
//   浏览器无需配对即可直接访问 ledgers / categories / assets。
// - mock_server 启动方式:
//     python3 tools/mock_server/server.py
// - 关闭 mock 模式:把 proxy 注释掉,改回指向真 gridly app (8123 同 port,
//   但 host 是 dev machine LAN IP)。
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: '0.0.0.0',
    proxy: {
      '/api': {
        target: 'http://localhost:8123',
        changeOrigin: false,
        // cookie 透传:默认就会透,但写出来明确一下
        // secure: false 因为 mock http
      },
    },
  },
});