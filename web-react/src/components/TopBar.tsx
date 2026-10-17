// 顶部 nav:Linear 风,贴边全宽,左 logo+nav,右 controls,16px 横向内边距
import { useNavigate, useLocation } from 'react-router-dom';
import { useTheme, useThemeMode } from '../theme';
import { api } from '../api/client';
import { Logo } from './Logo';

export default function TopBar() {
  const navigate = useNavigate();
  const location = useLocation();
  const theme = useTheme();
  const { mode, toggle } = useThemeMode();

  const logout = async () => {
    try {
      await api.logout();
    } catch {
      // 即使失败也跳走
    }
    navigate('/login');
    setTimeout(() => window.location.reload(), 50);
  };

  const navItem = (path: string, label: string) => {
    const active = location.pathname === path;
    return (
      <button
        onClick={() => navigate(path)}
        className="nav-item"
        style={{
          background: active ? theme.surfaceAlt : 'transparent',
          border: 'none',
          color: active ? theme.textPrimary : theme.textSecondary,
          fontSize: 12,
          fontWeight: active ? 600 : 500,
          cursor: 'pointer',
          padding: '5px 10px',
          borderRadius: theme.radius.md,
          fontFamily: theme.fontFamily,
        }}
      >
        {label}
      </button>
    );
  };

  return (
    <nav
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 4,
        padding: '6px 0',
        background: theme.surface,
        borderBottom: `1px solid ${theme.border}`,
        position: 'sticky',
        top: 0,
        zIndex: 10,
      }}
    >
      <div style={{ flex: '0 0 16px' }} />
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 6,
          fontSize: 13,
          fontWeight: 600,
          color: theme.textPrimary,
          marginRight: 4,
        }}
      >
        <Logo size={16} mode={mode} />
        gridly
      </div>
      {navItem('/', '流水')}
      {navItem('/sessions', '设备')}
      <div style={{ flex: 1 }} />
      <div style={{ flex: '0 0 16px' }} />
      <div style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
        <button
          onClick={toggle}
          title={mode === 'light' ? '切换到深色' : '切换到浅色'}
          style={{
            background: 'transparent',
            border: 'none',
            color: theme.textSecondary,
            fontSize: 12,
            cursor: 'pointer',
            padding: '4px 10px',
            borderRadius: theme.radius.md,
            fontFamily: theme.fontFamily,
          }}
          onMouseEnter={(e) => (e.currentTarget.style.background = theme.surfaceAlt)}
          onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
        >
          {mode === 'light' ? '🌙' : '☀️'}
        </button>
        <button
          onClick={logout}
          style={{
            background: 'transparent',
            border: 'none',
            color: theme.textSecondary,
            fontSize: 12,
            cursor: 'pointer',
            padding: '4px 10px',
            borderRadius: theme.radius.md,
            fontFamily: theme.fontFamily,
          }}
          onMouseEnter={(e) => (e.currentTarget.style.background = theme.surfaceAlt)}
          onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
        >
          登出
        </button>
      </div>
    </nav>
  );
}