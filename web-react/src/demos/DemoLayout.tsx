// 共享布局:顶部栏 + 摘要 + 表格
// 3 套 demo 用同一份代码,只换 theme
import { useMemo, useState } from 'react';
import { useReactTable, getCoreRowModel, flexRender, type ColumnDef } from '@tanstack/react-table';

export interface Ledger {
  id: string;
  date: string;
  type: 'expense' | 'income' | 'transfer';
  category: string;
  amount: number;
  account: string;
  note: string;
}

export interface Theme {
  name: string;
  primary: string;
  primaryFg: string;
  bg: string;
  surface: string;
  border: string;
  textPrimary: string;
  textSecondary: string;
  expense: string;
  income: string;
  transfer: string;
  fontFamily: string;
  fontFamilyMono: string;
}

const fmt = (n: number) =>
  n.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const typeLabel = (t: Ledger['type']) =>
  ({ expense: '支出', income: '收入', transfer: '调拨' }[t]);

const typeColor = (t: Ledger['type'], theme: Theme) =>
  ({ expense: theme.expense, income: theme.income, transfer: theme.transfer }[t]);

export function DemoLayout({ theme, data }: { theme: Theme; data: Ledger[] }) {
  const [month, setMonth] = useState('2026-10');
  const [filterType, setFilterType] = useState<'all' | Ledger['type']>('all');
  const [search, setSearch] = useState('');

  // 摘要:本月支出/收入/净
  const summary = useMemo(() => {
    const expense = data
      .filter((d) => d.type === 'expense' && d.date.startsWith(month))
      .reduce((s, d) => s + d.amount, 0);
    const income = data
      .filter((d) => d.type === 'income' && d.date.startsWith(month))
      .reduce((s, d) => s + d.amount, 0);
    return { expense, income, net: income - expense };
  }, [data, month]);

  // 筛选后的数据
  const filtered = useMemo(() => {
    return data.filter((d) => {
      if (filterType !== 'all' && d.type !== filterType) return false;
      if (search) {
        const q = search.toLowerCase();
        if (!`${d.category}${d.account}${d.note}`.toLowerCase().includes(q)) return false;
      }
      return true;
    });
  }, [data, filterType, search]);

  const columns = useMemo<ColumnDef<Ledger>[]>(
    () => [
      {
        header: '日期',
        accessorKey: 'date',
        size: 110,
        cell: (info) => <span style={{ color: theme.textSecondary }}>{info.getValue() as string}</span>,
      },
      {
        header: '类型',
        accessorKey: 'type',
        size: 80,
        cell: (info) => {
          const t = info.getValue() as Ledger['type'];
          return (
            <span
              style={{
                display: 'inline-block',
                padding: '2px 8px',
                borderRadius: 4,
                fontSize: 12,
                fontWeight: 500,
                color: typeColor(t, theme),
                background: `${typeColor(t, theme)}1A`,
              }}
            >
              {typeLabel(t)}
            </span>
          );
        },
      },
      {
        header: '分类',
        accessorKey: 'category',
        size: 100,
      },
      {
        header: '金额',
        accessorKey: 'amount',
        size: 120,
        cell: (info) => {
          const t = info.row.original.type;
          return (
            <span
              style={{
                fontFamily: theme.fontFamilyMono,
                fontWeight: 600,
                color: typeColor(t, theme),
                textAlign: 'right',
                display: 'block',
              }}
            >
              {t === 'expense' ? '-' : t === 'income' ? '+' : ''}
              {fmt(info.getValue() as number)}
            </span>
          );
        },
      },
      {
        header: '账户',
        accessorKey: 'account',
        size: 140,
        cell: (info) => <span style={{ color: theme.textSecondary }}>{info.getValue() as string}</span>,
      },
      {
        header: '备注',
        accessorKey: 'note',
        cell: (info) => <span style={{ color: theme.textSecondary }}>{info.getValue() as string || '—'}</span>,
      },
    ],
    [theme]
  );

  const table = useReactTable({
    data: filtered,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

  return (
    <div
      style={{
        minHeight: '100vh',
        background: theme.bg,
        fontFamily: theme.fontFamily,
        color: theme.textPrimary,
      }}
    >
      {/* 顶部栏 */}
      <header
        style={{
          height: 56,
          padding: '0 24px',
          background: theme.surface,
          borderBottom: `1px solid ${theme.border}`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
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
          <span style={{ fontSize: 16, fontWeight: 600 }}>gridly</span>
          <span style={{ color: theme.textSecondary, fontSize: 13 }}>· 局域网记账</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <span style={{ color: theme.textSecondary, fontSize: 13 }}>
            配对码 <strong style={{ fontFamily: theme.fontFamilyMono, color: theme.primary }}>824 913</strong> ·
            剩余 4:32
          </span>
          <button
            style={{
              background: theme.primary,
              color: theme.primaryFg,
              border: 'none',
              padding: '6px 14px',
              borderRadius: 6,
              fontSize: 13,
              fontWeight: 500,
              cursor: 'pointer',
            }}
          >
            + 记一笔
          </button>
          <span style={{ color: theme.textSecondary, fontSize: 13 }}>登出</span>
        </div>
      </header>

      {/* 主区域 */}
      <main style={{ maxWidth: 1200, margin: '0 auto', padding: '32px 24px' }}>
        <h1 style={{ margin: 0, fontSize: 22, fontWeight: 600 }}>{theme.name}</h1>
        <p style={{ margin: '4px 0 24px', color: theme.textSecondary, fontSize: 13 }}>
          表格样式 demo · 同布局不同配色/字体,你看哪个最对味
        </p>

        {/* 摘要卡 */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(3, 1fr)',
            gap: 16,
            marginBottom: 24,
          }}
        >
          <SummaryCard theme={theme} label={`${month} 支出`} value={summary.expense} color={theme.expense} />
          <SummaryCard theme={theme} label={`${month} 收入`} value={summary.income} color={theme.income} />
          <SummaryCard theme={theme} label={`${month} 结余`} value={summary.net} color={theme.primary} />
        </div>

        {/* 筛选条 */}
        <div
          style={{
            display: 'flex',
            gap: 12,
            marginBottom: 12,
            alignItems: 'center',
          }}
        >
          <select
            value={month}
            onChange={(e) => setMonth(e.target.value)}
            style={{
              padding: '6px 10px',
              border: `1px solid ${theme.border}`,
              borderRadius: 6,
              fontSize: 13,
              background: theme.surface,
              color: theme.textPrimary,
              fontFamily: theme.fontFamily,
            }}
          >
            <option value="2026-10">2026 年 10 月</option>
            <option value="2026-09">2026 年 9 月</option>
          </select>
          <div style={{ display: 'flex', gap: 4 }}>
            {(['all', 'expense', 'income', 'transfer'] as const).map((t) => (
              <button
                key={t}
                onClick={() => setFilterType(t)}
                style={{
                  padding: '6px 12px',
                  border: `1px solid ${theme.border}`,
                  background: filterType === t ? theme.primary : theme.surface,
                  color: filterType === t ? theme.primaryFg : theme.textPrimary,
                  borderRadius: 6,
                  fontSize: 13,
                  cursor: 'pointer',
                  fontFamily: theme.fontFamily,
                }}
              >
                {t === 'all' ? '全部' : typeLabel(t)}
              </button>
            ))}
          </div>
          <input
            type="text"
            placeholder="搜索分类/账户/备注"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{
              flex: 1,
              padding: '6px 12px',
              border: `1px solid ${theme.border}`,
              borderRadius: 6,
              fontSize: 13,
              background: theme.surface,
              color: theme.textPrimary,
              fontFamily: theme.fontFamily,
              outline: 'none',
            }}
          />
        </div>

        {/* 表格 */}
        <div
          style={{
            background: theme.surface,
            border: `1px solid ${theme.border}`,
            borderRadius: 8,
            overflow: 'hidden',
          }}
        >
          <table
            style={{
              width: '100%',
              borderCollapse: 'collapse',
              fontSize: 14,
            }}
          >
            <thead style={{ background: theme.bg }}>
              {table.getHeaderGroups().map((hg) => (
                <tr key={hg.id}>
                  {hg.headers.map((h) => (
                    <th
                      key={h.id}
                      style={{
                        textAlign: 'left',
                        padding: '10px 16px',
                        fontWeight: 600,
                        fontSize: 12,
                        color: theme.textSecondary,
                        textTransform: 'uppercase',
                        letterSpacing: 0.5,
                        borderBottom: `1px solid ${theme.border}`,
                        width: h.getSize(),
                      }}
                    >
                      {flexRender(h.column.columnDef.header, h.getContext())}
                    </th>
                  ))}
                </tr>
              ))}
            </thead>
            <tbody>
              {table.getRowModel().rows.map((row) => (
                <tr
                  key={row.id}
                  style={{
                    borderBottom: `1px solid ${theme.border}`,
                    transition: 'background 0.1s',
                  }}
                  onMouseEnter={(e) => (e.currentTarget.style.background = theme.bg)}
                  onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
                >
                  {row.getVisibleCells().map((cell) => (
                    <td
                      key={cell.id}
                      style={{
                        padding: '10px 16px',
                        verticalAlign: 'middle',
                      }}
                    >
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}

function SummaryCard({ theme, label, value, color }: { theme: Theme; label: string; value: number; color: string }) {
  return (
    <div
      style={{
        background: theme.surface,
        border: `1px solid ${theme.border}`,
        borderRadius: 8,
        padding: '16px 20px',
      }}
    >
      <div style={{ fontSize: 12, color: theme.textSecondary, marginBottom: 4 }}>{label}</div>
      <div
        style={{
          fontSize: 24,
          fontWeight: 600,
          color,
          fontFamily: theme.fontFamilyMono,
        }}
      >
        ¥ {fmt(value)}
      </div>
    </div>
  );
}