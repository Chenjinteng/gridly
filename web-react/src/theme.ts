// Design A · Navy Classic (2026-10-17 user 拍板)
// 配色 + 字体,React 整个 app 用这套
export const theme = {
  name: 'gridly',
  // 色
  primary: '#1E3A8A',
  primaryFg: '#FFFFFF',
  primaryHover: '#1E40AF',
  bg: '#F8FAFC',
  surface: '#FFFFFF',
  surfaceAlt: '#F1F5F9',
  border: '#E2E8F0',
  borderStrong: '#CBD5E1',
  textPrimary: '#0F172A',
  textSecondary: '#64748B',
  textTertiary: '#94A3B8',
  // 类型色
  expense: '#DC2626',
  income: '#16A34A',
  transfer: '#6366F1',
  // 状态
  error: '#DC2626',
  success: '#16A34A',
  warning: '#D97706',
  // 字体
  fontFamily:
    '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif',
  fontFamilyMono: '"SF Mono", Menlo, Consolas, monospace',
  // 间距
  space: { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32 },
  // 圆角
  radius: { sm: 4, md: 6, lg: 8, xl: 12 },
  // 阴影
  shadow: {
    sm: '0 1px 2px rgba(15, 23, 42, 0.05)',
    md: '0 1px 3px rgba(15, 23, 42, 0.08), 0 1px 2px rgba(15, 23, 42, 0.04)',
  },
} as const;

export type Theme = typeof theme;