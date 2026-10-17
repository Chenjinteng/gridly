// Ledger 主页:摘要 + 筛选 + 表格
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  flexRender,
  type ColumnDef,
  type SortingState,
} from '@tanstack/react-table';
import { api, type Ledger, type Category, type Account, type LedgerType } from '../api/client';
import { useTheme } from '../theme';
import { TypeChip } from '../components/TypeChip';
import AddTransactionModal from '../components/AddTransactionModal';

const fmt = (n: number) =>
  n.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const monthKey = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
const monthLabel = (key: string) => {
  const [y, m] = key.split('-');
  return `${y} 年 ${parseInt(m)} 月`;
};
const monthOptions = (): string[] => {
  const out: string[] = [];
  const now = new Date();
  for (let i = 0; i < 6; i++) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    out.push(monthKey(d));
  }
  return out;
};

export default function Ledger() {
  const theme = useTheme();
  const [month, setMonth] = useState(monthKey(new Date()));
  const [filterType, setFilterType] = useState<'all' | LedgerType>('all');
  const [search, setSearch] = useState('');
  const [ledgers, setLedgers] = useState<Ledger[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [sorting, setSorting] = useState<SortingState>([{ id: 'occurredAt', desc: true }]);

  // 备注列宽 = 容器宽 - 其它固定列宽(让表格撑满整宽,在线表格感)
  const tableRef = useRef<HTMLDivElement>(null);
  const [noteSize, setNoteSize] = useState(400);
  useEffect(() => {
    const el = tableRef.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      const w = entry.contentRect.width - 2;
      // 固定列:日期 180 + 类型 96 + 分类 140 + 金额 160 + 账户 160 = 736
      setNoteSize(Math.max(240, w - 736));
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // 加载数据
  useEffect(() => {
    setLoading(true);
    setError(null);
    const [y, m] = month.split('-');
    const from = `${y}-${m}-01`;
    const lastDay = new Date(parseInt(y), parseInt(m), 0).getDate();
    const to = `${y}-${m}-${String(lastDay).padStart(2, '0')}`;

    Promise.all([
      api.listLedgers({ from, to, limit: 500 }),
      api.listCategories(),
      api.listAccounts(),
    ])
      .then(([l, c, a]) => {
        setLedgers(l);
        setCategories(c);
        setAccounts(a);
      })
      .catch((e) => setError(e instanceof Error ? e.message : '加载失败'))
      .finally(() => setLoading(false));
  }, [month]);

  // 摘要
  const summary = useMemo(() => {
    const expense = ledgers
      .filter((d) => d.type === 'expense')
      .reduce((s, d) => s + d.amount, 0);
    const income = ledgers
      .filter((d) => d.type === 'income')
      .reduce((s, d) => s + d.amount, 0);
    return { expense, income, net: income - expense };
  }, [ledgers]);

  // 筛选
  const filtered = useMemo(() => {
    return ledgers.filter((d) => {
      if (filterType !== 'all' && d.type !== filterType) return false;
      if (search) {
        const q = search.toLowerCase();
        if (!`${d.categoryName ?? ''}${d.accountName ?? ''}${d.note ?? ''}`.toLowerCase().includes(q))
          return false;
      }
      return true;
    });
  }, [ledgers, filterType, search]);

  // 表格列
  const columns = useMemo<ColumnDef<Ledger>[]>(
    () => [
      {
        header: '日期',
        accessorKey: 'occurredAt',
        size: 180,
        cell: (info) => {
          const dt = info.getValue() as string;
          return (
            <span style={{ color: theme.textSecondary, fontSize: 13 }}>
              {dt.replace('T', ' ').slice(0, 16)}
            </span>
          );
        },
      },
      {
        header: '类型',
        accessorKey: 'type',
        size: 96,
        cell: (info) => <TypeChip type={info.getValue() as LedgerType} />,
      },
      {
        header: '分类',
        accessorFn: (row) => row.categoryName ?? `#${row.categoryId}`,
        id: 'categoryName',
        size: 140,
      },
      {
        header: '金额',
        accessorKey: 'amount',
        size: 160,
        cell: (info) => {
          const t = info.row.original.type;
          const c = t === 'expense' ? theme.expense : t === 'income' ? theme.income : theme.transfer;
          return (
            <span
              style={{
                fontFamily: theme.fontFamilyMono,
                fontWeight: 500,
                color: c,
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
        accessorFn: (row) => row.accountName ?? `#${row.accountId}`,
        id: 'accountName',
        size: 160,
        cell: (info) => <span style={{ color: theme.textSecondary }}>{info.getValue() as string}</span>,
      },
      {
        header: '备注',
        accessorFn: (row) => row.note ?? '',
        id: 'note',
        size: noteSize,
        cell: (info) => (
          <span style={{ color: theme.textSecondary }}>
            {(info.getValue() as string) || '—'}
          </span>
        ),
      },
    ],
    [theme, noteSize]
  );

  const table = useReactTable({
    data: filtered,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  });

  function handleAdded() {
    setShowAdd(false);
    // 重 load
    setLoading(true);
    const [y, m] = month.split('-');
    const from = `${y}-${m}-01`;
    const lastDay = new Date(parseInt(y), parseInt(m), 0).getDate();
    const to = `${y}-${m}-${String(lastDay).padStart(2, '0')}`;
    api
      .listLedgers({ from, to, limit: 500 })
      .then(setLedgers)
      .catch((e) => setError(e instanceof Error ? e.message : '重新加载失败'))
      .finally(() => setLoading(false));
  }

  return (
    <main
      style={{
        padding: '20px 16px',
      }}
    >
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          marginBottom: 16,
        }}
      >
        <h1 style={{ margin: 0, fontSize: 16, fontWeight: 700, flex: 1 }}>流水</h1>
        <button
          onClick={() => setShowAdd(true)}
          style={{
            background: theme.primary,
            color: theme.primaryFg,
            border: 'none',
            padding: '5px 12px',
            borderRadius: theme.radius.md,
            fontSize: 12,
            fontWeight: 600,
            cursor: 'pointer',
            fontFamily: theme.fontFamily,
          }}
        >
          + 记一笔
        </button>
      </div>

      {/* 摘要 */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
          gap: 8,
          marginBottom: 16,
        }}
      >
        <SummaryCard label={`${monthLabel(month)} 支出`} value={summary.expense} color={theme.expense} theme={theme} />
        <SummaryCard label={`${monthLabel(month)} 收入`} value={summary.income} color={theme.income} theme={theme} />
        <SummaryCard label={`${monthLabel(month)} 结余`} value={summary.net} color={theme.primary} theme={theme} />
      </div>

      {/* 筛选 */}
      <div style={{ display: 'flex', gap: 6, marginBottom: 12, alignItems: 'center' }}>
        <select
          value={month}
          onChange={(e) => setMonth(e.target.value)}
          style={{
            padding: '4px 10px',
            border: `1px solid ${theme.border}`,
            borderRadius: theme.radius.md,
            fontSize: 12,
            background: theme.surface,
            color: theme.textPrimary,
            fontFamily: theme.fontFamily,
            outline: 'none',
          }}
        >
          {monthOptions().map((m) => (
            <option key={m} value={m}>
              {monthLabel(m)}
            </option>
          ))}
        </select>
        <div
          style={{
            display: 'flex',
            border: `1px solid ${theme.border}`,
            borderRadius: theme.radius.md,
            overflow: 'hidden',
          }}
        >
          {(['all', 'expense', 'income', 'transfer'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setFilterType(t)}
              style={{
                padding: '4px 10px',
                border: 'none',
                background: filterType === t ? theme.primary : 'transparent',
                color: filterType === t ? theme.primaryFg : theme.textSecondary,
                fontSize: 12,
                cursor: 'pointer',
                fontFamily: theme.fontFamily,
              }}
            >
              {t === 'all' ? '全部' : ({ expense: '支出', income: '收入', transfer: '调拨' } as const)[t]}
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
            minWidth: 0,
            padding: '4px 10px',
            border: `1px solid ${theme.border}`,
            borderRadius: theme.radius.md,
            fontSize: 12,
            background: theme.surface,
            color: theme.textPrimary,
            fontFamily: theme.fontFamily,
            outline: 'none',
          }}
        />
      </div>

      {error && (
        <div
          style={{
            background: '#FEF2F2',
            color: theme.error,
            padding: '12px 16px',
            borderRadius: theme.radius.md,
            fontSize: 13,
            marginBottom: 12,
          }}
        >
          ⚠️ {error}
        </div>
      )}

      {/* 表格 */}
      <div
        ref={tableRef}
        style={{
          overflowX: 'auto',
        }}
      >
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
          <thead>
            {table.getHeaderGroups().map((hg) => (
              <tr key={hg.id}>
                {hg.headers.map((h) => (
                  <th
                    key={h.id}
                    onClick={h.column.getToggleSortingHandler()}
                    style={{
                      textAlign: 'left',
                      padding: '12px 14px',
                      fontWeight: 500,
                      fontSize: 11,
                      color: theme.textSecondary,
                      borderBottom: `1px solid ${theme.border}`,
                      width: h.getSize(),
                      cursor: h.column.getCanSort() ? 'pointer' : 'default',
                      userSelect: 'none',
                      whiteSpace: 'nowrap',
                      background: 'transparent',
                    }}
                  >
                    {flexRender(h.column.columnDef.header, h.getContext())}
                    {h.column.getIsSorted() === 'asc' ? ' ↑' : h.column.getIsSorted() === 'desc' ? ' ↓' : ''}
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={columns.length} style={{ padding: 40, textAlign: 'center', color: theme.textSecondary }}>
                  加载中…
                </td>
              </tr>
            ) : table.getRowModel().rows.length === 0 ? (
              <tr>
                <td colSpan={columns.length} style={{ padding: 40, textAlign: 'center', color: theme.textSecondary }}>
                  {monthLabel(month)} 没有流水
                </td>
              </tr>
            ) : (
              table.getRowModel().rows.map((row, idx) => (
                <tr
                  key={row.id}
                  style={{ borderBottom: idx === table.getRowModel().rows.length - 1 ? 'none' : `1px solid ${theme.border}` }}
                  onMouseEnter={(e) => (e.currentTarget.style.background = theme.surfaceAlt)}
                  onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
                >
                  {row.getVisibleCells().map((cell) => (
                    <td key={cell.id} style={{ padding: '16px 14px', verticalAlign: 'middle' }}>
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {showAdd && (
        <AddTransactionModal
          categories={categories}
          accounts={accounts}
          onClose={() => setShowAdd(false)}
          onAdded={handleAdded}
        />
      )}
    </main>
  );
}

const SummaryCard = ({ label, value, color, theme: t }: { label: string; value: number; color: string; theme: ReturnType<typeof useTheme> }) => (
  <div
    style={{
      padding: '20px 20px',
      minHeight: 88,
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'space-between',
    }}
  >
    <div style={{ fontSize: 11, color: t.textSecondary, fontWeight: 500, textTransform: 'uppercase', letterSpacing: 0.4 }}>{label}</div>
    <div
      style={{
        fontSize: 28,
        fontWeight: 600,
        color,
        fontFamily: t.fontFamilyMono,
        fontVariantNumeric: 'tabular-nums',
        letterSpacing: '-0.5px',
      }}
    >
      ¥ {fmt(value)}
    </div>
  </div>
);
