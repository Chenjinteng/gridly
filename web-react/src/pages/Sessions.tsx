// Sessions: 列出已配对设备,支持 revoke
import { useEffect, useState } from 'react';
import { api, type Session } from '../api/client';
import { theme } from '../theme';

function relTime(iso: string): string {
  const dt = new Date(iso);
  const diff = (Date.now() - dt.getTime()) / 1000;
  if (diff < 60) return '刚刚';
  if (diff < 3600) return `${Math.floor(diff / 60)} 分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 小时前`;
  if (diff < 86400 * 7) return `${Math.floor(diff / 86400)} 天前`;
  return dt.toLocaleDateString('zh-CN');
}

export default function Sessions() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    load();
  }, []);

  function load() {
    setLoading(true);
    setError(null);
    api
      .listSessions()
      .then(setSessions)
      .catch((e) => setError(e instanceof Error ? e.message : '加载失败'))
      .finally(() => setLoading(false));
  }

  async function revoke(token: string) {
    if (!confirm('撤销此设备的访问?该设备需重新配对才能继续使用。')) return;
    try {
      await api.revokeSession(token);
      load();
    } catch (e) {
      alert('撤销失败: ' + (e instanceof Error ? e.message : '未知错误'));
    }
  }

  return (
    <main style={{ maxWidth: 900, margin: '0 auto', padding: '32px 24px' }}>
      <h1 style={{ margin: '0 0 24px', fontSize: 22, fontWeight: 600 }}>已配对设备</h1>

      {error && (
        <div
          style={{
            background: '#FEF2F2',
            color: theme.error,
            padding: '12px 16px',
            borderRadius: theme.radius.md,
            fontSize: 13,
            marginBottom: 16,
          }}
        >
          ⚠️ {error}
        </div>
      )}

      <div
        style={{
          background: theme.surface,
          border: `1px solid ${theme.border}`,
          borderRadius: theme.radius.lg,
          overflow: 'hidden',
        }}
      >
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: theme.textSecondary }}>加载中…</div>
        ) : sessions.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: theme.textSecondary }}>没有已配对设备</div>
        ) : (
          sessions.map((s) => (
            <div
              key={s.token}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 12,
                padding: '14px 16px',
                borderBottom: `1px solid ${theme.border}`,
              }}
            >
              <div style={{ fontSize: 24 }}>{s.deviceIcon || '🌐'}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 500, color: theme.textPrimary }}>
                  {s.deviceName}
                  {s.isCurrent && (
                    <span
                      style={{
                        marginLeft: 8,
                        fontSize: 11,
                        background: theme.primary,
                        color: theme.primaryFg,
                        padding: '1px 6px',
                        borderRadius: theme.radius.sm,
                        fontWeight: 600,
                      }}
                    >
                      当前
                    </span>
                  )}
                </div>
                <div style={{ fontSize: 12, color: theme.textSecondary, marginTop: 2 }}>
                  最后活跃 {relTime(s.lastActiveAt)} · 配对于{' '}
                  {new Date(s.createdAt).toLocaleDateString('zh-CN')}
                </div>
              </div>
              {!s.isCurrent && (
                <button
                  onClick={() => revoke(s.token)}
                  style={{
                    background: 'none',
                    border: `1px solid ${theme.border}`,
                    color: theme.error,
                    padding: '4px 12px',
                    borderRadius: theme.radius.md,
                    fontSize: 12,
                    cursor: 'pointer',
                    fontFamily: theme.fontFamily,
                  }}
                >
                  撤销
                </button>
              )}
            </div>
          ))
        )}
      </div>

      <p style={{ marginTop: 16, color: theme.textSecondary, fontSize: 12 }}>
        配对码 5 分钟有效,配对后 cookie 7 天有效,过期后需重新配对。
      </p>
    </main>
  );
}