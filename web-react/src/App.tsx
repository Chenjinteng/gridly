// App: 路由 + auth gate
// - 未登录: 显 Login 页
// - 已登录: 显 Ledger 页(顶部栏可切 Sessions)
import { useEffect, useState } from 'react';
import { Routes, Route, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { api, ApiError } from './api/client';
import Login from './pages/Login';
import Ledger from './pages/Ledger';
import Sessions from './pages/Sessions';
import TopBar from './components/TopBar';
import { theme } from './theme';

export default function App() {
  const [authed, setAuthed] = useState<boolean | null>(null); // null = checking
  const location = useLocation();
  const navigate = useNavigate();

  // 检查 session 是否有效:用真正需要 auth 的 endpoint
  // (listSessions 是 public,不能用作 auth 探测)
  useEffect(() => {
    api
      .listLedgers({ limit: 1 })
      .then(() => setAuthed(true))
      .catch((e) => {
        if (e instanceof ApiError && (e.status === 401 || e.status === 403)) {
          setAuthed(false);
        } else {
          setAuthed(false);
        }
      });
  }, []);

  if (authed === null) {
    return (
      <div style={{ padding: 80, textAlign: 'center', color: theme.textSecondary }}>
        加载中…
      </div>
    );
  }

  return (
    <div style={{ minHeight: '100vh', background: theme.bg, fontFamily: theme.fontFamily }}>
      {authed && location.pathname !== '/login' && <TopBar />}
      <Routes>
        <Route
          path="/login"
          element={
            authed ? (
              <Navigate to="/" replace />
            ) : (
              <Login onPaired={() => { setAuthed(true); navigate('/'); }} />
            )
          }
        />
        <Route
          path="/"
          element={authed ? <Ledger /> : <Navigate to="/login" replace />}
        />
        <Route
          path="/sessions"
          element={authed ? <Sessions /> : <Navigate to="/login" replace />}
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </div>
  );
}