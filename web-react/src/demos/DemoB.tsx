// Design B: 翠绿 + Inter 字体 (清新 / 现代)
// 配色: emerald primary + 浅米色背景
import { useState } from 'react';
import { DemoLayout, type Ledger } from './DemoLayout';

const seedData: Ledger[] = [
  { id: '1', date: '2026-10-17', type: 'expense', category: '餐饮', amount: 38.5, account: '现金', note: '午餐' },
  { id: '2', date: '2026-10-17', type: 'expense', category: '交通', amount: 12, account: '微信', note: '地铁' },
  { id: '3', date: '2026-10-16', type: 'income', category: '工资', amount: 12000, account: '银行卡', note: '10月' },
  { id: '4', date: '2026-10-16', type: 'expense', category: '购物', amount: 286, account: '支付宝', note: '日用品' },
  { id: '5', date: '2026-10-15', type: 'expense', category: '居家', amount: 156, account: '银行卡', note: '水电' },
  { id: '6', date: '2026-10-15', type: 'transfer', category: '账户', amount: 500, account: '现金→银行卡', note: '' },
  { id: '7', date: '2026-10-14', type: 'expense', category: '娱乐', amount: 88, account: '支付宝', note: '电影' },
  { id: '8', date: '2026-10-14', type: 'expense', category: '餐饮', amount: 168, account: '银行卡', note: '聚餐' },
];

export default function DemoB() {
  const [theme] = useState({
    name: 'B · Emerald Modern',
    primary: '#059669',
    primaryFg: '#FFFFFF',
    bg: '#FAF7F2',
    surface: '#FFFFFF',
    border: '#E7E5E4',
    textPrimary: '#1C1917',
    textSecondary: '#78716C',
    expense: '#E11D48',
    income: '#059669',
    transfer: '#7C3AED',
    fontFamily: '"Inter", "Helvetica Neue", system-ui, sans-serif',
    fontFamilyMono: '"JetBrains Mono", "SF Mono", monospace',
  });
  return <DemoLayout theme={theme} data={seedData} />;
}