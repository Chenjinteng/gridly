// TypeChip + helpers
import { theme } from '../theme';
import type { LedgerType } from '../api/client';

const typeColor = (t: LedgerType) =>
  ({ expense: theme.expense, income: theme.income, transfer: theme.transfer }[t]);

const typeLabel = (t: LedgerType) =>
  ({ expense: '支出', income: '收入', transfer: '调拨' }[t]);

export function TypeChip({ type }: { type: LedgerType }) {
  const color = typeColor(type);
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '2px 8px',
        borderRadius: theme.radius.sm,
        fontSize: 12,
        fontWeight: 500,
        color,
        background: `${color}1A`,
      }}
    >
      {typeLabel(type)}
    </span>
  );
}

export function typeColorOf(t: LedgerType) {
  return typeColor(t);
}

export function typeLabelOf(t: LedgerType) {
  return typeLabel(t);
}