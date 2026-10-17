// 顶部栏:logo + 配对码 + 记一笔 + 导航 + 登出
import { useNavigate, useLocation } from 'react-router-dom';
import { theme } from '../theme';
import { api } from '../api/client';

export default function TopBar() {
  const navigate = useNavigate();
  const location = useLocation();

  const logout = async () => {
    try {
      await api.logout();
    } catch {
      // 即使失败也跳走
    }
    navigate('/login');
    // 强制刷新让 App 重检 auth
    setTimeout(() => window.location.reload(), 50);
  };

  const navItem = (path: string, label: string) => {
    const active = location.pathname === path;
    return (
      <button
        onClick={() => navigate(path)}
        style={{
          background: 'none',
          border: 'none',
          color: active ? theme.primary : theme.textSecondary,
          fontSize: 13,
          fontWeight: active ? 600 : 500,
          cursor: 'pointer',
          padding: '4px 8px',
          fontFamily: theme.fontFamily,
        }}
      >
        {label}
      </button>
    );
  };

  return (
    <header
      style={{
        height: 56,
        padding: '0 24px',
        background: theme.surface,
        borderBottom: `1px solid ${theme.border}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        position: 'sticky',
        top: 0,
        zIndex: 10,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div
            style={{
              width: 28,
              height: 28,
              background: theme.primary,
              borderRadius: 6,
              display: 'grid',
              placeItems: 'center',
              color: theme.primaryFg,
              fontWeight: 700,
              fontSize: 14,
            }}
          >
            ▦
          </div>
          <span style={{ fontSize: 16, fontWeight: 600, color: theme.textPrimary }}>gridly</span>
          <span style={{ color: theme.textTertiary, fontSize: 13 }}>· 局域网记账</span>
        </div>
        <nav style={{ display: 'flex', gap: 4 }}>
          {navItem('/', '流水')}
          {navItem('/sessions', '设备')}
        </nav>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
        <span style={{ color: theme.textSecondary, fontSize: 13 }}>
          配对码{' '}
          <strong style={{ fontFamily: theme.fontFamilyMono, color: theme.primary }}>
            通过 server 读
          </strong>
        </span>
        <button
          onClick={logout}
          style={{
            background: 'none',
            border: 'none',
            color: theme.textSecondary,
            fontSize: 13,
            cursor: 'pointer',
            fontFamily: theme.fontFamily,
          }}
        >
          登出
        </button>
      </div>
    </header>
  );
}