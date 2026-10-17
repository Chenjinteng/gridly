// Login: 6 位配对码 + device name
// 流程:
// 1. 自动从 server GET /api/auth/code 拉配对码(用户需在 mobile app 看同样码)
// 2. 用户确认 device name 后调 POST /api/auth/pair
// 3. 成功 → server set cookie 7 天,onPaired() 跳首页
import { useEffect, useState } from 'react';
import { api, ApiError, type PairingCode } from '../api/client';
import { useTheme, useThemeMode } from '../theme';
import { Logo } from '../components/Logo';

interface Props {
  onPaired: () => void;
}

function useCountdown(deadline: Date | null) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);
  if (!deadline) return 0;
  return Math.max(0, Math.floor((deadline.getTime() - now) / 1000));
}

function formatTime(s: number) {
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${m}:${sec.toString().padStart(2, '0')}`;
}

function defaultDeviceName(): string {
  const ua = navigator.userAgent;
  if (/Chrome\/(\d+)/.test(ua) && /Mac/.test(ua)) return 'Chrome (macOS)';
  if (/Chrome/.test(ua) && /Windows/.test(ua)) return 'Chrome (Windows)';
  if (/Chrome/.test(ua)) return 'Chrome';
  if (/Safari/.test(ua) && /Mac/.test(ua)) return 'Safari (macOS)';
  if (/Firefox/.test(ua)) return 'Firefox';
  return 'Web 浏览器';
}

function defaultDeviceIcon(): string {
  if (/Mac/.test(navigator.userAgent)) return '💻';
  if (/Windows/.test(navigator.userAgent)) return '🖥️';
  if (/Linux/.test(navigator.userAgent)) return '🐧';
  return '🌐';
}

export default function Login({ onPaired }: Props) {
  const theme = useTheme();
  const { mode } = useThemeMode();
  const [pairing, setPairing] = useState<PairingCode | null>(null);
  const [pairingError, setPairingError] = useState<string | null>(null);
  const [deviceName, setDeviceName] = useState(defaultDeviceName());
  const [deviceIcon, setDeviceIcon] = useState(defaultDeviceIcon());
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  const secondsLeft = useCountdown(pairing ? new Date(pairing.expiresAt) : null);

  // 自动拉配对码
  useEffect(() => {
    refreshCode();
  }, []);

  async function refreshCode() {
    setPairingError(null);
    try {
      const code = await api.getPairingCode();
      setPairing(code);
    } catch (e) {
      setPairingError(e instanceof Error ? e.message : '拉取配对码失败');
    }
  }

  async function handlePair(e: React.FormEvent) {
    e.preventDefault();
    if (!pairing) return;
    setSubmitting(true);
    setSubmitError(null);
    try {
      await api.pair(pairing.code, deviceName, deviceIcon);
      onPaired();
    } catch (err) {
      if (err instanceof ApiError) {
        if (err.status === 401) {
          setSubmitError('配对码错误或已过期,请刷新');
          refreshCode();
        } else {
          setSubmitError(`配对失败 (${err.status})`);
        }
      } else {
        setSubmitError(err instanceof Error ? err.message : '未知错误');
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'grid',
        placeItems: 'center',
        background: theme.bg,
        padding: 24,
      }}
    >
      <div
        style={{
          width: '100%',
          maxWidth: 400,
          background: theme.surface,
          border: `1px solid ${theme.border}`,
          borderRadius: theme.radius.lg,
          padding: '32px 32px',
        }}
      >
        <div style={{ textAlign: 'center', marginBottom: 24 }}>
          <div
            style={{
              width: 56,
              height: 56,
              background: theme.surfaceAlt,
              border: `1px solid ${theme.border}`,
              borderRadius: theme.radius.md,
              display: 'grid',
              placeItems: 'center',
              margin: '0 auto 16px',
            }}
          >
            <Logo size={36} mode={mode} />
          </div>
          <h1 style={{ margin: 0, fontSize: 18, color: theme.textPrimary, fontWeight: 700 }}>连接 gridly</h1>
          <p style={{ margin: '4px 0 0', color: theme.textSecondary, fontSize: 12 }}>
            在手机 app「设置 → 局域网 Web」查看配对码
          </p>
        </div>

        {pairingError ? (
          <div
            style={{
              background: 'rgba(235, 87, 87, 0.1)',
              border: `1px solid ${theme.error}`,
              color: theme.error,
              padding: '10px 12px',
              borderRadius: theme.radius.md,
              fontSize: 12,
              marginBottom: 16,
            }}
          >
            ⚠️ {pairingError} <button onClick={refreshCode} style={{ marginLeft: 8, color: theme.error, background: 'none', border: 'none', cursor: 'pointer', textDecoration: 'underline' }}>重试</button>
          </div>
        ) : pairing ? (
          <>
            <div
              style={{
                textAlign: 'center',
                padding: '20px 0',
                marginBottom: 20,
                background: theme.surfaceAlt,
                borderRadius: theme.radius.md,
              }}
            >
              <div
                style={{
                  fontFamily: theme.fontFamilyMono,
                  fontSize: 32,
                  fontWeight: 600,
                  letterSpacing: 8,
                  color: theme.primary,
                }}
              >
                {pairing.code.slice(0, 3)} {pairing.code.slice(3)}
              </div>
              <div style={{ marginTop: 8, color: theme.textSecondary, fontSize: 12 }}>
                剩余 {formatTime(secondsLeft)}{' '}
                <button
                  onClick={refreshCode}
                  style={{
                    background: 'none',
                    border: 'none',
                    color: theme.primary,
                    cursor: 'pointer',
                    fontSize: 12,
                    padding: 0,
                    marginLeft: 4,
                    fontFamily: theme.fontFamily,
                  }}
                >
                  刷新
                </button>
              </div>
            </div>

            <form onSubmit={handlePair}>
              <label
                style={{
                  display: 'block',
                  fontSize: 12,
                  color: theme.textSecondary,
                  marginBottom: 6,
                  fontWeight: 500,
                }}
              >
                设备名
              </label>
              <input
                value={deviceName}
                onChange={(e) => setDeviceName(e.target.value)}
                maxLength={32}
                style={{
                  width: '100%',
                  padding: '6px 10px',
                  border: `1px solid ${theme.border}`,
                  borderRadius: theme.radius.md,
                  fontSize: 13,
                  background: theme.surface,
                  color: theme.textPrimary,
                  fontFamily: theme.fontFamily,
                  outline: 'none',
                  boxSizing: 'border-box',
                  marginBottom: 14,
                }}
              />

              <label
                style={{
                  display: 'block',
                  fontSize: 12,
                  color: theme.textSecondary,
                  marginBottom: 6,
                  fontWeight: 500,
                }}
              >
                设备图标
              </label>
              <div style={{ display: 'flex', gap: 6, marginBottom: 20, flexWrap: 'wrap' }}>
                {['💻', '🖥️', '🌐', '🏠', '📱', '🐧'].map((emoji) => (
                  <button
                    key={emoji}
                    type="button"
                    onClick={() => setDeviceIcon(emoji)}
                    style={{
                      width: 36,
                      height: 36,
                      fontSize: 18,
                      border: `1px solid ${deviceIcon === emoji ? theme.primary : theme.border}`,
                      background: deviceIcon === emoji ? theme.surfaceAlt : theme.surface,
                      borderRadius: theme.radius.md,
                      cursor: 'pointer',
                    }}
                  >
                    {emoji}
                  </button>
                ))}
              </div>

              {submitError && (
                <div
                  style={{
                    background: 'rgba(235, 87, 87, 0.1)',
                    color: theme.error,
                    padding: '6px 10px',
                    borderRadius: theme.radius.sm,
                    fontSize: 12,
                    marginBottom: 10,
                  }}
                >
                  {submitError}
                </div>
              )}

              <button
                type="submit"
                disabled={submitting || secondsLeft === 0}
                style={{
                  width: '100%',
                  padding: '8px',
                  background: theme.primary,
                  color: theme.primaryFg,
                  border: 'none',
                  borderRadius: theme.radius.md,
                  fontSize: 13,
                  fontWeight: 600,
                  cursor: submitting || secondsLeft === 0 ? 'not-allowed' : 'pointer',
                  opacity: submitting || secondsLeft === 0 ? 0.6 : 1,
                  fontFamily: theme.fontFamily,
                }}
              >
                {submitting ? '配对中…' : '连接'}
              </button>
            </form>
          </>
        ) : (
          <div style={{ textAlign: 'center', padding: 40, color: theme.textSecondary }}>
            加载配对码…
          </div>
        )}
      </div>
    </div>
  );
}