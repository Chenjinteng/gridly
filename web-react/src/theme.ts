// Design W5 · Linear 风 (2026-10-17 user 拍板,v2.2.0)
// 配色 + 字体,React 整个 app 用这套
// Light + Dark 两套,ThemeContext 切换
// Linear 风:贴边 nav、紧凑、数据密集、Linear 紫 #5E6AD2
import { createContext, useContext } from 'react';

export interface Theme {
  name: 'gridly';
  mode: 'light' | 'dark';
  // 色
  primary: string;
  primaryFg: string;
  accent: string;
  bg: string;
  surface: string;
  surfaceAlt: string;
  border: string;
  borderStrong: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  // 类型色
  expense: string;
  income: string;
  transfer: string;
  // 状态
  error: string;
  success: string;
  warning: string;
  // 字体
  fontFamily: string;
  fontFamilyMono: string;
  // 圆角(Linear 小圆角)
  radius: { sm: number; md: number; lg: number };
  // 阴影(Linear 几乎无阴影)
  shadow: { sm: string };
}

const baseFontFamily =
  '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, "PingFang SC", "Microsoft YaHei", sans-serif';
const baseFontFamilyMono = '"SF Mono", "JetBrains Mono", Menlo, Consolas, monospace';

export const lightTheme: Theme = {
  name: 'gridly',
  mode: 'light',
  primary: '#5E6AD2',
  primaryFg: '#FFFFFF',
  accent: '#5E6AD2',
  bg: '#FBFBFB',
  surface: '#FFFFFF',
  surfaceAlt: '#F5F5F6',
  border: '#E8E8EA',
  borderStrong: '#D4D4D8',
  textPrimary: '#0F1419',
  textSecondary: '#62666D',
  textTertiary: '#95989D',
  expense: '#EB5757',
  income: '#0E9F6E',
  transfer: '#62666D',
  error: '#EB5757',
  success: '#0E9F6E',
  warning: '#F2C94C',
  fontFamily: baseFontFamily,
  fontFamilyMono: baseFontFamilyMono,
  radius: { sm: 4, md: 6, lg: 8 },
  shadow: { sm: '0 1px 1px rgba(15, 20, 25, 0.04)' },
};

export const darkTheme: Theme = {
  ...lightTheme,
  mode: 'dark',
  primary: '#9FA6F0',
  primaryFg: '#08090A',
  accent: '#9FA6F0',
  bg: '#08090A',
  surface: '#131416',
  surfaceAlt: '#1C1D20',
  border: '#2C2D31',
  borderStrong: '#3A3C41',
  textPrimary: '#F6F8FA',
  textSecondary: '#B4B8BF',
  textTertiary: '#6F7278',
  expense: '#F87171',
  income: '#4ADE80',
  transfer: '#B4B8BF',
  error: '#F87171',
  success: '#4ADE80',
  warning: '#FBBF24',
  shadow: { sm: '0 1px 1px rgba(0, 0, 0, 0.4)' },
};

export type ThemeMode = 'light' | 'dark';

interface ThemeContextValue {
  theme: Theme;
  mode: ThemeMode;
  toggle: () => void;
  setMode: (mode: ThemeMode) => void;
}

export const ThemeContext = createContext<ThemeContextValue>({
  theme: lightTheme,
  mode: 'light',
  toggle: () => {},
  setMode: () => {},
});

export function useTheme(): Theme {
  return useContext(ThemeContext).theme;
}

export function useThemeMode(): ThemeContextValue {
  return useContext(ThemeContext);
}

export const theme = lightTheme; // 向后兼容(给 module-level const 如 TypeChip 静态映射用)