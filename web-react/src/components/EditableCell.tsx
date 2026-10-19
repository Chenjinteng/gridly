// EditableCell:点 cell → input → Enter 保存 / Esc 取消 / blur 也保存(若变更)
// 乐观更新(更新本地 state),失败 revert + toast
import { useEffect, useRef, useState } from 'react';

interface Props {
  value: string;
  type?: 'text' | 'number';
  placeholder?: string;
  align?: 'left' | 'right';
  /** commit 时回调(可能因为没变更而返回 void) */
  onCommit: (next: string) => Promise<void>;
  style?: React.CSSProperties;
}

export function EditableCell({ value, type = 'text', placeholder, align = 'left', onCommit, style }: Props) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(value);
  const [saving, setSaving] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setDraft(value);
  }, [value]);

  useEffect(() => {
    if (editing) {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
  }, [editing]);

  async function commit() {
    const next = draft.trim();
    if (next === value) {
      setEditing(false);
      return;
    }
    setSaving(true);
    try {
      await onCommit(next);
      setEditing(false);
    } catch (e) {
      // revert
      setDraft(value);
      setEditing(false);
      alert(`保存失败: ${e instanceof Error ? e.message : '未知错误'}`);
    } finally {
      setSaving(false);
    }
  }

  function cancel() {
    setDraft(value);
    setEditing(false);
  }

  if (editing) {
    return (
      <input
        ref={inputRef}
        type={type}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            commit();
          } else if (e.key === 'Escape') {
            e.preventDefault();
            cancel();
          }
        }}
        disabled={saving}
        style={{
          width: '100%',
          padding: '4px 6px',
          fontSize: 13,
          fontFamily: type === 'number' ? '"SF Mono", "JetBrains Mono", Menlo, monospace' : 'inherit',
          background: 'transparent',
          color: 'inherit',
          border: '1px solid #5E6AD2',
          borderRadius: 4,
          outline: 'none',
          textAlign: align,
        }}
      />
    );
  }

  return (
    <span
      onDoubleClick={() => setEditing(true)}
      title="双击编辑"
      style={{
        cursor: 'text',
        padding: '2px 0',
        borderBottom: '1px dashed transparent',
        ...style,
      }}
      onMouseEnter={(e) => (e.currentTarget.style.borderBottom = '1px dashed #5E6AD2')}
      onMouseLeave={(e) => (e.currentTarget.style.borderBottom = '1px dashed transparent')}
    >
      {value || <span style={{ opacity: 0.4 }}>{placeholder ?? '—'}</span>}
    </span>
  );
}