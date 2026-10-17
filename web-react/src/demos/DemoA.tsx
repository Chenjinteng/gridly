// Design A: 商务深蓝 + macOS 系统字体
// 配色: navy primary + 灰白背景 + 经典会计软件色
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

export default function DemoA() {
  const [theme] = useState({
    name: 'A · Navy Classic',
    primary: '#1E3A8A',
    primaryFg: '#FFFFFF',
    bg: '#F8FAFC',
    surface: '#FFFFFF',
    border: '#E2E8F0',
    textPrimary: '#0F172A',
    textSecondary: '#64748B',
    expense: '#DC2626',
    income: '#16A34A',
    transfer: '#6366F1',
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif',
    fontFamilyMono: '"SF Mono", Menlo, Consolas, monospace',
  });
  return <DemoLayout theme={theme} data={seedData} />;
}