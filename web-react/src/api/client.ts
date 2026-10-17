// API client for gridly REST API (P2 endpoints)
// cookie-based auth:7 天 session,所有请求带 credentials: 'include'
//
// LAN_WEB P4 mock mode (2026-10-17 加):
// - 默认走 Vite proxy:fetch 相对路径 '/api/...' → Vite 把 /api/* 转发到
//   http://localhost:8123(参见 web-react/vite.config.ts)。
// - 优点:Set-Cookie 落在 5173 origin 下,后续 fetch 自动带,
//   跟 cross-origin fetch 没有 Secure/SameSite 兼容问题。
// - 真 app 模式:export VITE_API_BASE=http://192.168.x.x:8123 直接打真 server,
//   走 macOS / iOS app 的 LAN 配对流程(参见 docs/LAN_WEB.md)。

const API_BASE = import.meta.env.VITE_API_BASE ?? '';

export class ApiError extends Error {
  constructor(public status: number, message: string, public body?: unknown) {
    super(message);
  }
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
    ...options,
  });
  if (!res.ok) {
    let body: unknown;
    try {
      body = await res.json();
    } catch {
      body = await res.text();
    }
    throw new ApiError(res.status, `${options.method ?? 'GET'} ${path} → ${res.status}`, body);
  }
  // 204 No Content
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

// ===== Types (跟 Dart schema 1:1) =====

export type LedgerType = 'expense' | 'income' | 'transfer';
export type AccountType = 'cash' | 'bank' | 'wallet' | 'investment' | 'benefit' | 'fixed_asset' | 'receivable' | 'other';
export type CategoryType = 'cash_flow' | 'investment' | 'benefit' | 'fixed_asset' | 'receivable' | 'other';

export interface Ledger {
  id: number;
  amount: number;
  type: LedgerType;
  categoryId: number;
  occurredAt: string; // ISO datetime
  note: string | null;
  accountId: number;
  destinationAccountId: number | null;
  // joined (server 加的,方便前端展示)
  categoryName?: string;
  accountName?: string;
  destAccountName?: string | null;
}

export interface Category {
  id: number;
  name: string;
  icon: string;
  color: number;
  type: CategoryType;
  isSystem: boolean;
  sortOrder: number;
}

export interface Account {
  id: number;
  name: string;
  type: AccountType;
  icon: string;
  color: number;
  initialBalance: number;
  includeInTransactions: boolean;
  isDefault: boolean;
  actAsCashFlow: boolean;
  isLender: boolean;
  displayOrder: number;
  // computed (server 加的)
  balance?: number;
}

export interface Session {
  token: string;
  deviceName: string;
  deviceIcon: string;
  lastActiveAt: string;
  createdAt: string;
  isCurrent: boolean;
}

export interface HealthInfo {
  name: string;
  version: string;
  build: number;
  phase: string;
  dbSchemaVersion: number;
  transactions: number;
  categories: number;
  assets: number;
  uptimeSeconds: number;
  serverTime: string;
}

export interface PairingCode {
  code: string;
  expiresAt: string;
  secondsRemaining: number;
}

export interface MonthlyStat {
  month: string; // YYYY-MM
  expense: number;
  income: number;
  net: number;
  count: number;
}

// ===== Endpoints =====

export const api = {
  health: () => request<HealthInfo>('/api/health'),

  // Auth
  getPairingCode: () => request<PairingCode>('/api/auth/code'),
  pair: (code: string, deviceName: string, deviceIcon: string) =>
    request<{ token: string; expiresAt: string }>('/api/auth/pair', {
      method: 'POST',
      body: JSON.stringify({ code, deviceName, deviceIcon }),
    }),
  logout: () => request<void>('/api/auth/logout', { method: 'POST' }),
  listSessions: () => request<Session[]>('/api/auth/sessions'),
  revokeSession: (token: string) =>
    request<void>(`/api/auth/sessions/${encodeURIComponent(token)}`, { method: 'DELETE' }),

  // Ledgers
  listLedgers: async (params?: { from?: string; to?: string; type?: LedgerType; limit?: number }) => {
    const qs = new URLSearchParams();
    if (params?.from) qs.set('from', params.from);
    if (params?.to) qs.set('to', params.to);
    if (params?.type) qs.set('type', params.type);
    if (params?.limit) qs.set('pageSize', String(params.limit));
    const res = await request<{ ledgers: Ledger[]; page: number; pageSize: number }>(
      `/api/ledgers${qs.toString() ? '?' + qs : ''}`
    );
    return res.ledgers;
  },
  getLedger: (id: number) => request<{ ledger: Ledger }>(`/api/ledgers/${id}`).then((r) => r.ledger),
  createLedger: async (data: Omit<Ledger, 'id' | 'categoryName' | 'accountName' | 'destAccountName'>) => {
    const res = await request<{ ledger: Ledger }>('/api/ledgers', {
      method: 'POST',
      body: JSON.stringify(data),
    });
    return res.ledger;
  },
  updateLedger: (id: number, data: Partial<Ledger>) =>
    request<{ ledger: Ledger }>(`/api/ledgers/${id}`, { method: 'PUT', body: JSON.stringify(data) }).then(
      (r) => r.ledger
    ),
  deleteLedger: (id: number) => request<void>(`/api/ledgers/${id}`, { method: 'DELETE' }),

  // Categories & Accounts (for dropdowns)
  listCategories: () => request<Category[]>('/api/categories'),
  listAccounts: () => request<Account[]>('/api/assets'),

  // Stats
  monthlyStats: (params?: { from?: string; to?: string }) => {
    const qs = new URLSearchParams();
    if (params?.from) qs.set('from', params.from);
    if (params?.to) qs.set('to', params.to);
    return request<MonthlyStat[]>(`/api/stats/monthly${qs.toString() ? '?' + qs : ''}`);
  },
};

export { API_BASE };