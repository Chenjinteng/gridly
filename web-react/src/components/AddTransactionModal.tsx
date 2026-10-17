// AddTransaction modal: 记一笔
// 简化:支出/收入/调拨 3 段 + 分类下拉(按 type 过滤) + 账户下拉 + 金额 + 备注 + 提交
// 不做批量录入(Phase 1 简化)
import { useMemo, useState } from 'react';
import { api, type Category, type Account, type LedgerType, type CategoryType } from '../api/client';
import { theme } from '../theme';

interface Props {
  categories: Category[];
  accounts: Account[];
  onClose: () => void;
  onAdded: () => void;
}

const type2cat: Record<LedgerType, CategoryType> = {
  expense: 'cash_flow',
  income: 'cash_flow',
  transfer: 'cash_flow', // 调拨也走 cash_flow(简化,server 端可能细分)
};

const typeLabel = (t: LedgerType) => ({ expense: '支出', income: '收入', transfer: '调拨' }[t]);

export default function AddTransactionModal({ categories, accounts, onClose, onAdded }: Props) {
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
    () => categories.filter((c) => c.type === type2cat[type] && !c.isSystem /* 默认系统类过滤 */),
    [categories, type]
  );

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
    <div
      onClick={onClose}
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(15, 23, 42, 0.4)',
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
          maxWidth: 480,
          background: theme.surface,
          borderRadius: theme.radius.xl,
          padding: 24,
          boxShadow: theme.shadow.md,
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
          <h2 style={{ margin: 0, fontSize: 18, fontWeight: 600 }}>记一笔</h2>
          <button
            onClick={onClose}
            style={{ background: 'none', border: 'none', fontSize: 20, color: theme.textTertiary, cursor: 'pointer' }}
          >
            ×
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          {/* 类型 */}
          <div style={{ display: 'flex', gap: 4, marginBottom: 16 }}>
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
                  padding: '8px 0',
                  border: `1px solid ${type === t ? theme.primary : theme.border}`,
                  background: type === t ? theme.primary : theme.surface,
                  color: type === t ? theme.primaryFg : theme.textPrimary,
                  borderRadius: theme.radius.md,
                  fontSize: 13,
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
          <div style={{ marginBottom: 16 }}>
            <label style={labelStyle}>金额</label>
            <input
              type="number"
              step="0.01"
              min="0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
              autoFocus
              style={{ ...inputStyle, fontSize: 20, fontFamily: theme.fontFamilyMono, fontWeight: 600 }}
            />
          </div>

          {/* 分类 */}
          <div style={{ marginBottom: 16 }}>
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
          <div style={{ marginBottom: 16 }}>
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
            <div style={{ marginBottom: 16 }}>
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
          <div style={{ marginBottom: 16 }}>
            <label style={labelStyle}>日期</label>
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              style={inputStyle}
            />
          </div>

          {/* 备注 */}
          <div style={{ marginBottom: 16 }}>
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
                background: '#FEF2F2',
                color: theme.error,
                padding: '8px 12px',
                borderRadius: theme.radius.sm,
                fontSize: 12,
                marginBottom: 12,
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
                padding: '8px 16px',
                background: theme.surface,
                color: theme.textPrimary,
                border: `1px solid ${theme.border}`,
                borderRadius: theme.radius.md,
                fontSize: 13,
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
                padding: '8px 20px',
                background: theme.primary,
                color: theme.primaryFg,
                border: 'none',
                borderRadius: theme.radius.md,
                fontSize: 13,
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
      </div>
    </div>
  );
}

const labelStyle: React.CSSProperties = {
  display: 'block',
  fontSize: 12,
  color: theme.textSecondary,
  marginBottom: 6,
  fontWeight: 500,
};

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '8px 12px',
  border: `1px solid ${theme.border}`,
  borderRadius: theme.radius.md,
  fontSize: 14,
  background: theme.surface,
  color: theme.textPrimary,
  fontFamily: theme.fontFamily,
  outline: 'none',
  boxSizing: 'border-box',
};