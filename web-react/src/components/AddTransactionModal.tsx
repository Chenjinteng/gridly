// AddTransaction modal: 记一笔 (Linear 风 — 紧凑、贴边风格)
// 两个 tab:
// - 单条:支出/收入/调拨 3 段 + 分类下拉 + 账户下拉 + 金额 + 备注 + 提交
// - 批量:粘贴 tab-separated 数据(每行 = 一笔),实时 preview + 校验 + 批量 POST
import { useMemo, useState } from 'react';
import { api, type Category, type Account, type LedgerType, type CategoryType } from '../api/client';
import { useTheme } from '../theme';

interface Props {
  categories: Category[];
  accounts: Account[];
  onClose: () => void;
  onAdded: () => void;
}

const type2cat: Record<LedgerType, CategoryType> = {
  expense: 'cash_flow',
  income: 'cash_flow',
  transfer: 'cash_flow',
};

const typeLabel = (t: LedgerType) => ({ expense: '支出', income: '收入', transfer: '调拨' }[t]);

type Tab = 'single' | 'batch';

interface ParsedRow {
  raw: string;
  ok: boolean;
  error?: string;
  data?: {
    type: LedgerType;
    occurredAt: string; // YYYY-MM-DD
    catName: string;
    amount: number;
    accountName: string;
    note: string;
  };
}

export default function AddTransactionModal({ categories, accounts, onClose, onAdded }: Props) {
  const theme = useTheme();
  const [tab, setTab] = useState<Tab>('single');

  return (
    <div
      onClick={onClose}
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(15, 20, 25, 0.5)',
        display: 'grid',
        placeItems: 'center',
        zIndex: 100,
        padding: 24,
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: '100%',
          maxWidth: tab === 'batch' ? 640 : 440,
          background: theme.surface,
          borderRadius: theme.radius.lg,
          padding: 20,
          border: `1px solid ${theme.border}`,
          maxHeight: '90vh',
          overflowY: 'auto',
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <h2 style={{ margin: 0, fontSize: 16, fontWeight: 700 }}>记一笔</h2>
          <button
            onClick={onClose}
            style={{
              background: 'transparent',
              border: 'none',
              fontSize: 18,
              color: theme.textTertiary,
              cursor: 'pointer',
              padding: 0,
              lineHeight: 1,
            }}
          >
            ×
          </button>
        </div>

        {/* Tab 切换 */}
        <div
          style={{
            display: 'flex',
            borderBottom: `1px solid ${theme.border}`,
            marginBottom: 16,
          }}
        >
          {(['single', 'batch'] as const).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              style={{
                padding: '6px 14px',
                border: 'none',
                background: 'transparent',
                color: tab === t ? theme.textPrimary : theme.textSecondary,
                fontSize: 12,
                fontWeight: tab === t ? 600 : 500,
                cursor: 'pointer',
                borderBottom: tab === t ? `2px solid ${theme.primary}` : '2px solid transparent',
                marginBottom: -1,
                fontFamily: theme.fontFamily,
              }}
            >
              {t === 'single' ? '单条' : '批量粘贴'}
            </button>
          ))}
        </div>

        {tab === 'single' ? (
          <SingleTab categories={categories} accounts={accounts} onClose={onClose} onAdded={onAdded} />
        ) : (
          <BatchTab categories={categories} accounts={accounts} onClose={onClose} onAdded={onAdded} />
        )}
      </div>
    </div>
  );
}

// ============================================================
// 单条 tab — 跟旧逻辑一致
// ============================================================
function SingleTab({
  categories,
  accounts,
  onClose,
  onAdded,
}: {
  categories: Category[];
  accounts: Account[];
  onClose: () => void;
  onAdded: () => void;
}) {
  const theme = useTheme();
  const [type, setType] = useState<LedgerType>('expense');
  const [categoryId, setCategoryId] = useState<number | ''>('');
  const [accountId, setAccountId] = useState<number | ''>(accounts[0]?.id ?? '');
  const [destAccountId, setDestAccountId] = useState<number | ''>('');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const filteredCats = useMemo(
    () => categories.filter((c) => c.type === type2cat[type] && !c.isSystem),
    [categories, type]
  );

  const labelStyle: React.CSSProperties = {
    display: 'block',
    fontSize: 12,
    color: theme.textSecondary,
    marginBottom: 6,
    fontWeight: 500,
  };

  const inputStyle: React.CSSProperties = {
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
  };

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!categoryId) {
      setError('请选择分类');
      return;
    }
    if (type !== 'transfer' && !accountId) {
      setError('请选择账户');
      return;
    }
    const amt = parseFloat(amount);
    if (!amt || amt <= 0) {
      setError('金额必须 > 0');
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      await api.createLedger({
        amount: amt,
        type,
        categoryId: categoryId as number,
        accountId: (accountId || 0) as number,
        destinationAccountId: type === 'transfer' ? (destAccountId as number) : null,
        occurredAt: `${date}T${new Date().toTimeString().slice(0, 8)}`,
        note: note.trim() || null,
      });
      onAdded();
    } catch (e) {
      setError(e instanceof Error ? e.message : '提交失败');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit}>
      {/* 类型 */}
      <div
        style={{
          display: 'flex',
          border: `1px solid ${theme.border}`,
          borderRadius: theme.radius.md,
          overflow: 'hidden',
          marginBottom: 14,
        }}
      >
        {(['expense', 'income', 'transfer'] as const).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => {
              setType(t);
              setCategoryId('');
            }}
            style={{
              flex: 1,
              padding: '6px 0',
              border: 'none',
              background: type === t ? theme.primary : 'transparent',
              color: type === t ? theme.primaryFg : theme.textSecondary,
              fontSize: 12,
              fontWeight: 500,
              cursor: 'pointer',
              fontFamily: theme.fontFamily,
            }}
          >
            {typeLabel(t)}
          </button>
        ))}
      </div>

      {/* 金额 */}
      <div style={{ marginBottom: 14 }}>
        <label style={labelStyle}>金额</label>
        <input
          type="number"
          step="0.01"
          min="0"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0.00"
          autoFocus
          style={{ ...inputStyle, fontSize: 18, fontFamily: theme.fontFamilyMono, fontWeight: 600 }}
        />
      </div>

      {/* 分类 */}
      <div style={{ marginBottom: 14 }}>
        <label style={labelStyle}>分类</label>
        <select
          value={categoryId}
          onChange={(e) => setCategoryId(e.target.value ? Number(e.target.value) : '')}
          style={inputStyle}
        >
          <option value="">选择分类…</option>
          {filteredCats.map((c) => (
            <option key={c.id} value={c.id}>
              {c.icon} {c.name}
            </option>
          ))}
        </select>
      </div>

      {/* 账户 */}
      <div style={{ marginBottom: 14 }}>
        <label style={labelStyle}>{type === 'transfer' ? '转出账户' : '账户'}</label>
        <select
          value={accountId}
          onChange={(e) => setAccountId(e.target.value ? Number(e.target.value) : '')}
          style={inputStyle}
        >
          <option value="">选择账户…</option>
          {accounts.map((a) => (
            <option key={a.id} value={a.id}>
              {a.icon} {a.name}
            </option>
          ))}
        </select>
      </div>

      {type === 'transfer' && (
        <div style={{ marginBottom: 14 }}>
          <label style={labelStyle}>转入账户</label>
          <select
            value={destAccountId}
            onChange={(e) => setDestAccountId(e.target.value ? Number(e.target.value) : '')}
            style={inputStyle}
          >
            <option value="">选择转入账户…</option>
            {accounts
              .filter((a) => a.id !== accountId)
              .map((a) => (
                <option key={a.id} value={a.id}>
                  {a.icon} {a.name}
                </option>
              ))}
          </select>
        </div>
      )}

      {/* 日期 */}
      <div style={{ marginBottom: 14 }}>
        <label style={labelStyle}>日期</label>
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          style={inputStyle}
        />
      </div>

      {/* 备注 */}
      <div style={{ marginBottom: 14 }}>
        <label style={labelStyle}>备注</label>
        <input
          type="text"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          maxLength={100}
          placeholder="(可选)"
          style={inputStyle}
        />
      </div>

      {error && (
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
          {error}
        </div>
      )}

      <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
        <button
          type="button"
          onClick={onClose}
          style={{
            padding: '6px 14px',
            background: theme.surface,
            color: theme.textPrimary,
            border: `1px solid ${theme.border}`,
            borderRadius: theme.radius.md,
            fontSize: 12,
            cursor: 'pointer',
            fontFamily: theme.fontFamily,
          }}
        >
          取消
        </button>
        <button
          type="submit"
          disabled={submitting}
          style={{
            padding: '6px 16px',
            background: theme.primary,
            color: theme.primaryFg,
            border: 'none',
            borderRadius: theme.radius.md,
            fontSize: 12,
            fontWeight: 600,
            cursor: submitting ? 'not-allowed' : 'pointer',
            opacity: submitting ? 0.6 : 1,
            fontFamily: theme.fontFamily,
          }}
        >
          {submitting ? '保存中…' : '保存'}
        </button>
      </div>
    </form>
  );
}

// ============================================================
// 批量 tab — 粘贴 tab-separated,实时解析 + preview + 批量 POST
// ============================================================
//
// 行格式(tab 或 4+ 空格分隔):
//   日期 \t 类型 \t 分类 \t 金额 \t 账户 \t 备注
// - 日期:YYYY-MM-DD,空 = 今天
// - 类型:支出 / 收入 / 调拨,空 = 支出
// - 分类:分类名(精确匹配),空 = 报错
// - 金额:正数
// - 账户:账户名(精确匹配),空 = 报错
// - 备注:可选
function parseBatch(input: string, cats: Category[], accs: Account[]): ParsedRow[] {
  const today = new Date().toISOString().slice(0, 10);
  return input
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#')) // 跳过空行 + # 注释
    .map((raw): ParsedRow => {
      // tab 或 4+ 空格分隔
      const cols = raw.split(/\t|\s{4,}/);
      const [dateS, typeS = '', catS, amtS, accS, ...noteParts] = cols;
      const note = noteParts.join(' ').trim();

      // 类型
      const tNorm = typeS.trim();
      let type: LedgerType | null = null;
      if (tNorm === '' || tNorm === '支出' || tNorm === 'expense') type = 'expense';
      else if (tNorm === '收入' || tNorm === 'income') type = 'income';
      else if (tNorm === '调拨' || tNorm === 'transfer' || tNorm === 'balance') type = 'transfer';
      if (!type) return { raw, ok: false, error: `类型"${tNorm}"不对(支出/收入/调拨)` };

      // 日期
      const date = dateS.trim() || today;
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return { raw, ok: false, error: `日期"${dateS}"格式不对(YYYY-MM-DD)` };

      // 分类(精确匹配)
      const catName = catS?.trim() ?? '';
      if (!catName) return { raw, ok: false, error: '分类为空' };
      const cat = cats.find((c) => c.name === catName);
      if (!cat) return { raw, ok: false, error: `找不到分类"${catName}"` };

      // 金额
      const amt = parseFloat((amtS ?? '').replace(/[¥$,\s]/g, ''));
      if (!Number.isFinite(amt) || amt <= 0)
        return { raw, ok: false, error: `金额"${amtS}"不对(正数)` };

      // 账户
      const accName = accS?.trim() ?? '';
      if (!accName) return { raw, ok: false, error: '账户为空' };
      const acc = accs.find((a) => a.name === accName);
      if (!acc) return { raw, ok: false, error: `找不到账户"${accName}"` };

      return {
        raw,
        ok: true,
        data: { type, occurredAt: date, catName, amount: amt, accountName: accName, note },
      };
    });
}

function BatchTab({
  categories,
  accounts,
  onClose,
  onAdded,
}: {
  categories: Category[];
  accounts: Account[];
  onClose: () => void;
  onAdded: () => void;
}) {
  const theme = useTheme();
  const [text, setText] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const rows = useMemo(() => parseBatch(text, categories, accounts), [text, categories, accounts]);
  const okRows = rows.filter((r) => r.ok);
  const badRows = rows.filter((r) => !r.ok);

  const placeholder = [
    '# 每行一笔,用 tab 或 4+ 空格分隔,日期空 = 今天',
    '# 格式:日期 \t 类型 \t 分类 \t 金额 \t 账户 \t 备注',
    '',
    '2026-10-18\t支出\t餐饮\t45.50\t银行卡\t午饭',
    '\t支出\t娱乐\t128\t银行卡\t电影',
    '2026-10-17\t收入\t工资\t12000\t银行卡',
  ].join('\n');

  async function handleImport() {
    if (okRows.length === 0) return;
    setError(null);
    setSubmitting(true);
    setProgress({ done: 0, total: okRows.length });
    let failed = 0;
    let success = 0;
    for (let i = 0; i < okRows.length; i++) {
      const r = okRows[i];
      const data = r.data!;
      const cat = categories.find((c) => c.name === data.catName)!;
      const acc = accounts.find((a) => a.name === data.accountName)!;
      try {
        await api.createLedger({
          amount: data.amount,
          type: data.type,
          categoryId: cat.id,
          accountId: acc.id,
          destinationAccountId: null,
          occurredAt: `${data.occurredAt}T12:00:00`,
          note: data.note || null,
        });
        success++;
      } catch {
        failed++;
      }
      setProgress({ done: i + 1, total: okRows.length });
    }
    setSubmitting(false);
    setProgress(null);
    if (failed > 0 && success > 0) {
      setError(`${success} 笔已导入,${failed} 笔失败,失败的可能余额不足 / 重复 / 服务器错误`);
    } else if (failed > 0) {
      setError(`${failed} 笔全部失败,可能余额不足 / 重复 / 服务器错误`);
    } else {
      onAdded();
    }
  }

  return (
    <div>
      <div style={{ marginBottom: 10, fontSize: 12, color: theme.textSecondary, lineHeight: 1.6 }}>
        粘贴 tab-separated / 空格对齐的流水(每行 1 笔)。
        日期空 = 今天;类型空 = 支出(支出/收入/调拨);分类 / 账户按名称精确匹配;备注可选。
      </div>

      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder={placeholder}
        rows={8}
        spellCheck={false}
        style={{
          width: '100%',
          padding: '8px 10px',
          border: `1px solid ${theme.border}`,
          borderRadius: theme.radius.md,
          fontSize: 12,
          background: theme.surface,
          color: theme.textPrimary,
          fontFamily: theme.fontFamilyMono,
          outline: 'none',
          boxSizing: 'border-box',
          resize: 'vertical',
          minHeight: 140,
        }}
      />

      {/* 解析结果统计 */}
      <div
        style={{
          display: 'flex',
          gap: 14,
          fontSize: 12,
          color: theme.textSecondary,
          marginTop: 8,
          marginBottom: 8,
        }}
      >
        <span>解析 {rows.length} 行</span>
        <span style={{ color: theme.income }}>{okRows.length} 笔可导入</span>
        {badRows.length > 0 && <span style={{ color: theme.error }}>{badRows.length} 笔有问题</span>}
      </div>

      {/* 预览表 */}
      {rows.length > 0 && (
        <div
          style={{
            border: `1px solid ${theme.border}`,
            borderRadius: theme.radius.md,
            maxHeight: 200,
            overflowY: 'auto',
            marginBottom: 10,
          }}
        >
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
            <thead style={{ position: 'sticky', top: 0, background: theme.bg }}>
              <tr style={{ borderBottom: `1px solid ${theme.border}` }}>
                <th style={{ padding: '6px 8px', textAlign: 'left', fontWeight: 500, color: theme.textSecondary }}>日期</th>
                <th style={{ padding: '6px 8px', textAlign: 'left', fontWeight: 500, color: theme.textSecondary }}>类型</th>
                <th style={{ padding: '6px 8px', textAlign: 'left', fontWeight: 500, color: theme.textSecondary }}>分类</th>
                <th style={{ padding: '6px 8px', textAlign: 'right', fontWeight: 500, color: theme.textSecondary }}>金额</th>
                <th style={{ padding: '6px 8px', textAlign: 'left', fontWeight: 500, color: theme.textSecondary }}>账户</th>
                <th style={{ padding: '6px 8px', textAlign: 'left', fontWeight: 500, color: theme.textSecondary }}>备注</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) =>
                r.ok ? (
                  <tr key={i} style={{ borderBottom: `1px solid ${theme.border}` }}>
                    <td style={{ padding: '5px 8px', color: theme.textPrimary }}>{r.data!.occurredAt}</td>
                    <td style={{ padding: '5px 8px', color: theme.textSecondary }}>{typeLabel(r.data!.type)}</td>
                    <td style={{ padding: '5px 8px', color: theme.textPrimary }}>{r.data!.catName}</td>
                    <td style={{ padding: '5px 8px', textAlign: 'right', color: theme.textPrimary, fontFamily: theme.fontFamilyMono }}>
                      {r.data!.amount.toFixed(2)}
                    </td>
                    <td style={{ padding: '5px 8px', color: theme.textSecondary }}>{r.data!.accountName}</td>
                    <td style={{ padding: '5px 8px', color: theme.textTertiary }}>{r.data!.note || '—'}</td>
                  </tr>
                ) : (
                  <tr
                    key={i}
                    title={r.error}
                    style={{ borderBottom: `1px solid ${theme.border}`, background: 'rgba(235, 87, 87, 0.08)' }}
                  >
                    <td colSpan={5} style={{ padding: '5px 8px', color: theme.error }}>
                      <span style={{ fontFamily: theme.fontFamilyMono }}>{r.raw}</span>
                    </td>
                    <td style={{ padding: '5px 8px', color: theme.error, fontSize: 11 }}>{r.error}</td>
                  </tr>
                )
              )}
            </tbody>
          </table>
        </div>
      )}

      {error && (
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
          {error}
        </div>
      )}

      {progress && (
        <div style={{ fontSize: 12, color: theme.textSecondary, marginBottom: 10 }}>
          正在导入… {progress.done} / {progress.total}
        </div>
      )}

      <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
        <button
          type="button"
          onClick={onClose}
          disabled={submitting}
          style={{
            padding: '6px 14px',
            background: theme.surface,
            color: theme.textPrimary,
            border: `1px solid ${theme.border}`,
            borderRadius: theme.radius.md,
            fontSize: 12,
            cursor: submitting ? 'not-allowed' : 'pointer',
            fontFamily: theme.fontFamily,
          }}
        >
          取消
        </button>
        <button
          type="button"
          onClick={handleImport}
          disabled={submitting || okRows.length === 0}
          style={{
            padding: '6px 16px',
            background: theme.primary,
            color: theme.primaryFg,
            border: 'none',
            borderRadius: theme.radius.md,
            fontSize: 12,
            fontWeight: 600,
            cursor: submitting || okRows.length === 0 ? 'not-allowed' : 'pointer',
            opacity: submitting || okRows.length === 0 ? 0.6 : 1,
            fontFamily: theme.fontFamily,
          }}
        >
          {submitting ? '导入中…' : `导入 ${okRows.length} 笔`}
        </button>
      </div>
    </div>
  );
}