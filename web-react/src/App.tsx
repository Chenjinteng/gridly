// App: ThemeProvider + 路由 + auth gate
// - 未登录: 显 Login 页
// - 已登录: 显 Ledger 页(顶部栏可切 Sessions)
import { useEffect, useMemo, useState } from 'react';
import { Routes, Route, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { api, ApiError } from './api/client';
import Login from './pages/Login';
import Ledger from './pages/Ledger';
import Sessions from './pages/Sessions';
import TopBar from './components/TopBar';
import { ThemeContext, lightTheme, darkTheme, type ThemeMode } from './theme';

export default function App() {
  const [authed, setAuthed] = useState<boolean | null>(null); // null = checking
  const [mode, setModeState] = useState<ThemeMode>(
    () => (localStorage.getItem('gridly-theme') as ThemeMode) || 'light'
  );
  const location = useLocation();
  const navigate = useNavigate();

  // 同步 mode 到 <html data-theme> + localStorage
  useEffect(() => {
    document.documentElement.dataset.theme = mode;
    localStorage.setItem('gridly-theme', mode);
  }, [mode]);

  const themeValue = useMemo(() => {
    const theme = mode === 'dark' ? darkTheme : lightTheme;
    return {
      theme,
      mode,
      toggle: () => setModeState((m) => (m === 'light' ? 'dark' : 'light')),
      setMode: (m: ThemeMode) => setModeState(m),
    };
  }, [mode]);

  // 检查 session 是否有效:用真正需要 auth 的 endpoint
  useEffect(() => {
    api
      .listLedgers({ limit: 1 })
      .then(() => setAuthed(true))
      .catch(() => setAuthed(false));
  }, []);

  if (authed === null) {
    return (
      <div
        style={{
          minHeight: '100vh',
          background: themeValue.theme.bg,
          color: themeValue.theme.textSecondary,
          display: 'grid',
          placeItems: 'center',
          fontFamily: themeValue.theme.fontFamily,
          fontSize: 13,
        }}
      >
        加载中…
      </div>
    );
  }

  return (
    <ThemeContext.Provider value={themeValue}>
      <div
        style={{
          minHeight: '100vh',
          background: themeValue.theme.bg,
          fontFamily: themeValue.theme.fontFamily,
          color: themeValue.theme.textPrimary,
          fontSize: 13,
        }}
      >
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
    </ThemeContext.Provider>
  );
}