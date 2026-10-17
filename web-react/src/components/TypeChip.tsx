// TypeChip + helpers
import { useTheme } from '../theme';
import type { LedgerType } from '../api/client';

const typeLabel = (t: LedgerType) =>
  ({ expense: '支出', income: '收入', transfer: '调拨' }[t]);

export function TypeChip({ type }: { type: LedgerType }) {
  const theme = useTheme();
  const color =
    type === 'expense' ? theme.expense : type === 'income' ? theme.income : theme.transfer;
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        padding: '2px 8px',
        borderRadius: theme.radius.sm,
        fontSize: 11,
        fontWeight: 500,
        color,
        background: `${color}1F`,
      }}
    >
      {typeLabel(type)}
    </span>
  );
}

export function typeLabelOf(t: LedgerType) {
  return typeLabel(t);
}