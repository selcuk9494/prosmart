import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import cors from 'cors';
import express from 'express';
import jwt from 'jsonwebtoken';
import multer from 'multer';
import pg from 'pg';
import { createWorker } from 'tesseract.js';

async function promptSecret(label) {
  if (!process.stdin.isTTY) {
    throw new Error('Missing env vars: PGPASSWORD');
  }

  return await new Promise((resolve, reject) => {
    const stdin = process.stdin;
    const stdout = process.stdout;
    let value = '';

    const cleanup = () => {
      stdin.setRawMode(false);
      stdin.pause();
      stdin.removeListener('data', onData);
    };

    const onData = (buf) => {
      const s = buf.toString('utf8');
      for (const ch of s) {
        if (ch === '\r' || ch === '\n') {
          stdout.write('\n');
          cleanup();
          resolve(value);
          return;
        }
        if (ch === '\u0003') {
          stdout.write('\n');
          cleanup();
          reject(new Error('Aborted'));
          return;
        }
        if (ch === '\u007f') {
          value = value.slice(0, -1);
          continue;
        }
        value += ch;
      }
    };

    stdout.write(label);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.on('data', onData);
  });
}

function signAccessToken(payload, jwtSecret) {
  return jwt.sign(payload, jwtSecret, { expiresIn: '30d' });
}

const app = express();
app.use(express.json({ limit: '2mb' }));
app.use(
  cors({
    origin: '*',
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    optionsSuccessStatus: 204,
  }),
);
app.options('*', cors({ origin: '*' }));

app.get('/', (req, res) => {
  res.json({ ok: true });
});

app.use((req, res, next) => {
  const startedAt = Date.now();
  const origin = (req.headers.origin ?? '').toString();
  const method = req.method;
  const path = req.originalUrl || req.url;
  res.on('finish', () => {
    const ms = Date.now() - startedAt;
    process.stdout.write(
      `${method} ${path} ${res.statusCode} ${ms}ms${origin ? ` origin=${origin}` : ''}\n`,
    );
  });
  next();
});

function authRequired(req, res, next) {
  const header = req.headers.authorization ?? '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }
  try {
    if (!jwtSecret) {
      return res.status(503).json({ error: 'AUTH_NOT_READY' });
    }
    req.user = jwt.verify(token, jwtSecret);
    return next();
  } catch {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }
}

function requireRole(role) {
  return (req, res, next) => {
    if (!req.user || req.user.role !== role) {
      return res.status(403).json({ error: 'FORBIDDEN' });
    }
    return next();
  };
}

function requireAnyRole(roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'FORBIDDEN' });
    }
    return next();
  };
}

function asyncRoute(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

function asDateString(value) {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) return null;
  return v;
}

function dateStringInTz(date, timeZone) {
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(date);
  } catch {
    const iso = new Date(date).toISOString();
    return iso.slice(0, 10);
  }
}

function istanbulDateString(offsetDays = 0) {
  const base = new Date(Date.now() + offsetDays * 24 * 60 * 60 * 1000);
  return dateStringInTz(base, 'Europe/Istanbul');
}

async function mapLimit(items, limit, fn) {
  const results = new Array(items.length);
  let nextIndex = 0;

  const worker = async () => {
    while (true) {
      const i = nextIndex;
      nextIndex++;
      if (i >= items.length) return;
      results[i] = await fn(items[i], i);
    }
  };

  const workers = [];
  const n = Math.max(1, Math.min(limit, items.length));
  for (let i = 0; i < n; i++) workers.push(worker());
  await Promise.all(workers);
  return results;
}

async function getAutomationUserId() {
  const row = await queryOne(
    `
    select id
    from app_users
    where is_active = true and role in ('manager', 'accounting')
    order by case when role = 'manager' then 0 else 1 end, created_at asc
    limit 1
    `,
    [],
  );
  return row?.id?.toString() || null;
}

async function ensureCashReconciliation({ branchId, businessDate, createdByUserId }) {
  const row = await queryOne(
    `
    insert into cash_reconciliations(branch_id, business_date, expected_sales_total, created_by_user_id)
    values (
      $1::uuid,
      $2::date,
      coalesce(
        (select gross_total from daily_sales where branch_id = $1 and business_date = $2::date limit 1),
        0
      ),
      $3::uuid
    )
    on conflict (branch_id, business_date)
    do update set updated_at = now()
    returning id
    `,
    [branchId, businessDate, createdByUserId],
  );
  return row?.id?.toString() || null;
}

function toMoney(value) {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const n = Number(value.replace(',', '.'));
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function toQty(value) {
  const v = toMoney(value);
  if (v == null) return null;
  return v;
}

async function queryOne(text, params) {
  const r = await pool.query(text, params);
  return r.rows[0] ?? null;
}

async function queryAll(text, params) {
  const r = await pool.query(text, params);
  return r.rows;
}

let pool;
let jwtSecret = '';

app.get(
  '/health',
  asyncRoute(async (req, res) => {
    const r = await queryOne('select 1 as ok', []);
    res.json({ ok: r?.ok === 1 });
  }),
);

app.get(
  '/health/db-check',
  asyncRoute(async (req, res) => {
    const requiredTables = [
      'inv_invoices',
      'inv_invoice_lines',
      'inv_products',
      'payment_types',
      'income_centers',
    ];
    const requiredColumns = {
      inv_invoices: [
        'id',
        'branch_id',
        'invoice_no',
        'invoice_date',
        'vendor_name',
        'notes',
        'payment_type_id',
        'income_center_id',
        'discount_rate',
        'discount_amount',
        'meal_voucher_discount',
        'payment_date',
      ],
      inv_invoice_lines: [
        'id',
        'invoice_id',
        'product_id',
        'description',
        'unit',
        'quantity',
        'unit_price',
      ],
    };

    const tableRows = await queryAll(
      `
      select table_name
      from information_schema.tables
      where table_schema='public' and table_name = any($1::text[])
      `,
      [requiredTables],
    );
    const existingTables = new Set(tableRows.map((r) => r.table_name));
    const missingTables = requiredTables.filter((t) => !existingTables.has(t));

    const tablesToCheckCols = Object.keys(requiredColumns);
    const colRows = await queryAll(
      `
      select table_name, column_name
      from information_schema.columns
      where table_schema='public' and table_name = any($1::text[])
      `,
      [tablesToCheckCols],
    );
    const existingCols = new Set(colRows.map((r) => `${r.table_name}.${r.column_name}`));
    const missingColumns = [];
    for (const [table, cols] of Object.entries(requiredColumns)) {
      for (const col of cols) {
        if (!existingCols.has(`${table}.${col}`)) missingColumns.push({ table, column: col });
      }
    }

    res.json({
      ok: missingTables.length === 0 && missingColumns.length === 0,
      missingTables,
      missingColumns,
      serverTime: new Date().toISOString(),
    });
  }),
);

app.post(
  '/auth/login',
  asyncRoute(async (req, res) => {
  const username = (req.body?.username ?? '').toString().trim();
  const password = (req.body?.password ?? '').toString();
  if (!username) return res.status(400).json({ error: 'USERNAME_REQUIRED' });

  const user = await queryOne(
    `
    select id, username, display_name, role, password_hash, is_active
    from app_users
    where username = $1
    `,
    [username],
  );

  if (!user || !user.is_active) return res.status(401).json({ error: 'INVALID_CREDENTIALS' });

  const hasPassword = (user.password_hash ?? '').toString().trim().length > 0;
  if (hasPassword) {
    const ok = await queryOne(`select crypt($1, $2) = $2 as ok`, [password, user.password_hash]);
    if (!ok?.ok) return res.status(401).json({ error: 'INVALID_CREDENTIALS' });
  }

  const branch = await queryOne(
    `
    select branch_id
    from user_branch_access
    where user_id = $1
    order by created_at asc
    limit 1
    `,
    [user.id],
  );

  const accessToken = signAccessToken({
    sub: user.id,
    username: user.username,
    role: user.role,
    branchId: branch?.branch_id ?? null,
  }, jwtSecret);

  res.json({
    accessToken,
    userId: user.id,
    displayName: user.display_name,
    role: user.role,
    branchId: branch?.branch_id ?? null,
  });
  }),
);

app.get(
  '/AntiForgery/SetCookie',
  asyncRoute(async (req, res) => {
    res.status(204).end();
  }),
);

app.post(
  '/api/services/app/Account/IsTenantAvailable',
  asyncRoute(async (req, res) => {
    const tenancyName = (req.body?.tenancyName ?? '').toString().trim() || null;
    res.json({
      result: {
        state: 1,
        tenantId: tenancyName ? 1 : null,
        tenancyName,
      },
      success: true,
      error: null,
      unAuthorizedRequest: false,
      __abp: true,
    });
  }),
);

app.post(
  '/api/TokenAuth/Authenticate',
  asyncRoute(async (req, res) => {
    const username = (req.body?.usernameOrEmailAddress ?? '').toString().trim();
    const password = (req.body?.password ?? '').toString();
    if (!username) {
      return res.status(200).json({
        result: null,
        success: false,
        error: { message: 'USERNAME_REQUIRED' },
        unAuthorizedRequest: false,
        __abp: true,
      });
    }

    const user = await queryOne(
      `
      select id, username, display_name, role, password_hash, is_active
      from app_users
      where username = $1
      `,
      [username],
    );

    if (!user || !user.is_active) {
      return res.status(200).json({
        result: null,
        success: false,
        error: { message: 'INVALID_CREDENTIALS' },
        unAuthorizedRequest: false,
        __abp: true,
      });
    }

    const hasPassword = (user.password_hash ?? '').toString().trim().length > 0;
    if (hasPassword) {
      const ok = await queryOne(`select crypt($1, $2) = $2 as ok`, [password, user.password_hash]);
      if (!ok?.ok) {
        return res.status(200).json({
          result: null,
          success: false,
          error: { message: 'INVALID_CREDENTIALS' },
          unAuthorizedRequest: false,
          __abp: true,
        });
      }
    }

    const branch = await queryOne(
      `
      select branch_id
      from user_branch_access
      where user_id = $1
      order by created_at asc
      limit 1
      `,
      [user.id],
    );

    const accessToken = signAccessToken(
      {
        sub: user.id,
        username: user.username,
        role: user.role,
        branchId: branch?.branch_id ?? null,
      },
      jwtSecret,
    );

    res.json({
      result: {
        accessToken,
        expireInSeconds: 30 * 24 * 60 * 60,
        userId: user.id,
      },
      success: true,
      error: null,
      unAuthorizedRequest: false,
      __abp: true,
    });
  }),
);

app.post(
  '/auth/change-password',
  authRequired,
  asyncRoute(async (req, res) => {
    const currentPassword = (req.body?.currentPassword ?? '').toString();
    const newPassword = (req.body?.newPassword ?? '').toString();

    const user = await queryOne(
      `select id, password_hash from app_users where id = $1::uuid`,
      [req.user.sub],
    );
    if (!user) return res.status(404).json({ error: 'NOT_FOUND' });

    const hasPassword = (user.password_hash ?? '').toString().trim().length > 0;
    if (hasPassword) {
      const ok = await queryOne(`select crypt($1, $2) = $2 as ok`, [
        currentPassword,
        user.password_hash,
      ]);
      if (!ok?.ok) return res.status(401).json({ error: 'INVALID_CREDENTIALS' });
    }

    if (newPassword.trim().length === 0) {
      await pool.query(
        `update app_users set password_hash = null, updated_at = now() where id = $1::uuid`,
        [req.user.sub],
      );
      return res.json({ ok: true, passwordRemoved: true });
    }

    await pool.query(
      `update app_users set password_hash = crypt($2, gen_salt('bf')), updated_at = now() where id = $1::uuid`,
      [req.user.sub, newPassword],
    );
    return res.json({ ok: true });
  }),
);

app.get(
  '/users',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const rows = await queryAll(
      `
      select
        id,
        username,
        display_name as "displayName",
        role,
        is_active as "isActive",
        created_at as "createdAt"
      from app_users
      order by created_at desc
      limit 1000
      `,
      [],
    );
    res.json(rows);
  }),
);

app.post(
  '/users',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const username = (req.body?.username ?? '').toString().trim();
    const displayName = (req.body?.displayName ?? '').toString().trim();
    const role = (req.body?.role ?? '').toString().trim();
    const password = (req.body?.password ?? '').toString();

    if (!username) return res.status(400).json({ error: 'USERNAME_REQUIRED' });
    if (!displayName) return res.status(400).json({ error: 'DISPLAY_NAME_REQUIRED' });
    if (!['manager', 'accounting', 'branchUser'].includes(role)) {
      return res.status(400).json({ error: 'ROLE_INVALID' });
    }

    const hasPassword = password.trim().length > 0;

    const row = await queryOne(
      `
      insert into app_users(username, display_name, password_hash, role, is_active)
      values (
        $1,
        $2,
        case when $3::boolean then crypt($4, gen_salt('bf')) else null end,
        $5,
        true
      )
      returning id
      `,
      [username, displayName, hasPassword, password, role],
    );

    res.json({ id: row.id });
  }),
);

app.patch(
  '/users/:id',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const displayName = (req.body?.displayName ?? '').toString().trim();
    const role = (req.body?.role ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;
    const password = (req.body?.password ?? null) == null ? null : (req.body.password ?? '').toString();

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };

    if (displayName) add('display_name = ?', displayName);
    if (role) {
      if (!['manager', 'accounting', 'branchUser'].includes(role)) {
        return res.status(400).json({ error: 'ROLE_INVALID' });
      }
      add('role = ?', role);
    }
    if (isActive != null) add('is_active = ?', isActive);

    if (password != null) {
      if (password.trim().length === 0) {
        sets.push('password_hash = null');
      } else {
        add('password_hash = crypt(?, gen_salt(\'bf\'))', password);
      }
    }

    if (sets.length === 0) return res.status(400).json({ error: 'NO_CHANGES' });

    sets.push('updated_at = now()');
    await pool.query(
      `update app_users set ${sets.join(', ')} where id = $1::uuid`,
      params,
    );
    res.json({ ok: true });
  }),
);

app.get(
  '/user-menu-permissions',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const userId = (req.query?.userId ?? '').toString().trim();
    if (!userId) return res.status(400).json({ error: 'USER_REQUIRED' });

    const rows = await queryAll(
      `
      select legacy_ref as "legacyRef"
      from user_menu_permissions
      where user_id = $1::uuid
      order by legacy_ref asc
      `,
      [userId],
    );
    res.json(rows.map((r) => r.legacyRef));
  }),
);

app.get(
  '/me/menu-permissions',
  authRequired,
  asyncRoute(async (req, res) => {
    const rows = await queryAll(
      `
      select legacy_ref as "legacyRef"
      from user_menu_permissions
      where user_id = $1::uuid
      order by legacy_ref asc
      `,
      [req.user.sub],
    );
    res.json(rows.map((r) => r.legacyRef));
  }),
);

app.put(
  '/user-menu-permissions/:userId',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const userId = req.params.userId;
    const refs = Array.isArray(req.body?.legacyRefs) ? req.body.legacyRefs : null;
    if (!refs) return res.status(400).json({ error: 'LEGACY_REFS_REQUIRED' });

    const normalized = [
      ...new Set(
        refs
          .map((x) => (x ?? '').toString().trim())
          .filter((x) => x.length > 0)
          .slice(0, 5000),
      ),
    ];

    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(`delete from user_menu_permissions where user_id = $1::uuid`, [userId]);
      for (const r of normalized) {
        await client.query(
          `insert into user_menu_permissions(user_id, legacy_ref) values ($1::uuid, $2)`,
          [userId, r],
        );
      }
      await client.query('commit');
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }

    res.json({ ok: true, count: normalized.length });
  }),
);

app.get(
  '/branches',
  authRequired,
  asyncRoute(async (req, res) => {
  try {
    const rows = await queryAll(
      `
      select
        id,
        code,
        name,
        business_day_start_hour as "businessDayStartHour",
        is_active as "isActive"
      from branches
      order by name asc
      `,
      [],
    );
    res.json(rows);
  } catch (e) {
    if (e?.code !== '42703') throw e;
    const rows = await queryAll(
      `
      select id, code, name, is_active as "isActive"
      from branches
      order by name asc
      `,
      [],
    );
    res.json(rows.map((r) => ({ ...r, businessDayStartHour: 0 })));
  }
  }),
);

app.get(
  '/reports/ana-grup-satis',
  authRequired,
  asyncRoute(async (req, res) => {
    const from = asDateString(req.query?.from);
    const to = asDateString(req.query?.to);
    const branchId = (req.query?.branchId ?? '').toString().trim() || null;

    if (branchId && !canAccessBranch(req, branchId)) {
      return res.status(403).json({ error: 'FORBIDDEN' });
    }

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };
    if (branchId) add('s.branch_id = ?::uuid', branchId);
    if (from) add('s.business_date >= ?::date', from);
    if (to) add('s.business_date <= ?::date', to);
    const where = filters.length ? `where ${filters.join(' and ')}` : '';

    const rows = await queryAll(
      `
      select
        b.id as "branchId",
        b.name as "branchName",
        coalesce(sum(s.gross_total), 0)::numeric(14,2) as "grossTotal"
      from branches b
      left join daily_sales s on s.branch_id = b.id
      ${where}
      group by b.id, b.name
      order by b.name asc
      `,
      params,
    );

    res.json(rows);
  }),
);

function slugify(raw) {
  const v = (raw ?? '').toString().trim().toLowerCase();
  const mapped = v
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ı', 'i')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 32);
  return mapped || 'item';
}

app.post(
  '/branches',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const name = (req.body?.name ?? '').toString().trim();
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });
    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw || `${slugify(name)}-${Math.floor(Math.random() * 9000 + 1000)}`;
    const businessDayStartHourRaw = req.body?.businessDayStartHour ?? 0;
    let businessDayStartHour = Number.parseInt((businessDayStartHourRaw ?? 0).toString(), 10);
    if (!Number.isFinite(businessDayStartHour)) businessDayStartHour = 0;
    if (businessDayStartHour < 0 || businessDayStartHour > 23) businessDayStartHour = 0;

    let row;
    try {
      row = await queryOne(
        `
        insert into branches(code, name, business_day_start_hour, is_active)
        values ($1, $2, $3::int, true)
        on conflict (code) do update set
          name = excluded.name,
          business_day_start_hour = excluded.business_day_start_hour,
          is_active = true,
          updated_at = now()
        returning id
        `,
        [code, name, businessDayStartHour],
      );
    } catch (e) {
      if (e?.code !== '42703') throw e;
      row = await queryOne(
        `
        insert into branches(code, name, is_active)
        values ($1, $2, true)
        on conflict (code) do update set
          name = excluded.name,
          is_active = true,
          updated_at = now()
        returning id
        `,
        [code, name],
      );
    }

    res.json({ id: row.id });
  }),
);

app.patch(
  '/branches/:id',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const hasCode = Object.prototype.hasOwnProperty.call(req.body ?? {}, 'code');
    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw ? codeRaw : null;
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;
    const hasBusinessDayStartHour = Object.prototype.hasOwnProperty.call(req.body ?? {}, 'businessDayStartHour');
    const businessDayStartHourRaw = req.body?.businessDayStartHour ?? null;
    let businessDayStartHour = null;
    if (hasBusinessDayStartHour) {
      const n = Number.parseInt((businessDayStartHourRaw ?? 0).toString(), 10);
      businessDayStartHour = Number.isFinite(n) ? n : 0;
      if (businessDayStartHour < 0 || businessDayStartHour > 23) businessDayStartHour = 0;
    }

    if (!name && !hasCode && isActive == null && !hasBusinessDayStartHour) {
      return res.status(400).json({ error: 'NO_CHANGES' });
    }

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (hasCode) add('code = ?', code);
    if (isActive != null) add('is_active = ?', isActive);
    if (hasBusinessDayStartHour) add('business_day_start_hour = ?::int', businessDayStartHour);
    sets.push('updated_at = now()');

    try {
      await pool.query(
        `update branches set ${sets.join(', ')} where id = $1::uuid`,
        params,
      );
    } catch (e) {
      if (e?.code !== '42703' || !hasBusinessDayStartHour) throw e;
      if (!name && !hasCode && isActive == null) {
        return res.status(400).json({ error: 'BUSINESS_DAY_START_HOUR_NOT_SUPPORTED' });
      }
      const fallbackSets = [];
      const fallbackParams = [id];
      const addFallback = (sql, value) => {
        fallbackParams.push(value);
        fallbackSets.push(sql.replace('?', `$${fallbackParams.length}`));
      };
      if (name) addFallback('name = ?', name);
      if (hasCode) addFallback('code = ?', code);
      if (isActive != null) addFallback('is_active = ?', isActive);
      fallbackSets.push('updated_at = now()');
      await pool.query(
        `update branches set ${fallbackSets.join(', ')} where id = $1::uuid`,
        fallbackParams,
      );
    }

    res.json({ ok: true });
  }),
);

app.get(
  '/branches/:id/cash-registers',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = req.params.id;
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const rows = await queryAll(
      `
      select
        cr.id,
        cr.code,
        cr.name,
        cr.is_active as "isActive"
      from branch_cash_registers bcr
      join cash_registers cr on cr.id = bcr.cash_register_id
      where bcr.branch_id = $1::uuid
      order by lower(cr.code) asc
      `,
      [branchId],
    );
    res.json(rows);
  }),
);

app.put(
  '/branches/:id/cash-registers',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = req.params.id;
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const idsRaw = req.body?.cashRegisterIds;
    const ids = Array.isArray(idsRaw)
      ? idsRaw.map((x) => (x ?? '').toString().trim()).filter((x) => x.length > 0)
      : null;
    if (!ids) return res.status(400).json({ error: 'CASH_REGISTER_IDS_REQUIRED' });

    const existing = await queryAll(
      `select id from cash_registers where id = any($1::uuid[])`,
      [ids],
    );
    const existingIds = new Set(existing.map((r) => r.id));
    const normalized = ids.filter((id) => existingIds.has(id));

    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(`delete from branch_cash_registers where branch_id = $1::uuid`, [branchId]);
      for (const id of normalized) {
        await client.query(
          `insert into branch_cash_registers(branch_id, cash_register_id) values ($1::uuid, $2::uuid)`,
          [branchId, id],
        );
      }
      await client.query('commit');
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }

    res.json({ ok: true, count: normalized.length });
  }),
);

function integrationSecretOrNull() {
  const v = (process.env.INTEGRATION_SECRET ?? '').toString().trim();
  return v || null;
}

function _parseMoneyLoose(val) {
  if (val === null || typeof val === 'undefined') return 0;
  if (typeof val === 'number') return Number.isFinite(val) ? val : 0;
  if (typeof val === 'string') {
    const s = val.trim();
    if (!s) return 0;
    const normalized = s.replace(/\./g, '').replace(',', '.');
    const n = Number.parseFloat(normalized);
    return Number.isFinite(n) ? n : 0;
  }
  const n = Number(val);
  return Number.isFinite(n) ? n : 0;
}

const _upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024 },
});

let _ocrWorker = null;
async function _ensureOcrWorker() {
  if (_ocrWorker) return _ocrWorker;
  const here = path.dirname(fileURLToPath(import.meta.url));
  const cachePath = process.env.VERCEL ? '/tmp/tessdata' : path.resolve(here, '.tessdata');
  try {
    await fs.mkdir(cachePath, { recursive: true });
  } catch {}
  _ocrWorker = await createWorker(['tur', 'eng'], 1, {
    langPath: here,
    cachePath,
  });
  return _ocrWorker;
}

function _sameDateString(a, b) {
  const aa = _normalizeDateValue(a);
  const bb = _normalizeDateValue(b);
  if (!aa || !bb) return false;
  return aa === bb;
}

function _pad2(n) {
  return n.toString().padStart(2, '0');
}

function _toDateString(y, m, d) {
  return `${y.toString().padStart(4, '0')}-${_pad2(m)}-${_pad2(d)}`;
}

function _normalizeDateValue(value) {
  if (!value) return null;
  if (typeof value === 'string') {
    const v = value.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
    const m = v.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (m) return `${m[1]}-${m[2]}-${m[3]}`;
    return null;
  }
  if (value instanceof Date) {
    return _toDateString(value.getFullYear(), value.getMonth() + 1, value.getDate());
  }
  return _normalizeDateValue(value.toString?.());
}

function _parseOcrDate(text) {
  const t = (text ?? '').toString();

  const months = {
    ocak: 1,
    'şubat': 2,
    subat: 2,
    mart: 3,
    nisan: 4,
    'mayıs': 5,
    mayis: 5,
    haziran: 6,
    temmuz: 7,
    'ağustos': 8,
    agustos: 8,
    'eylül': 9,
    eylul: 9,
    ekim: 10,
    'kasım': 11,
    kasim: 11,
    'aralık': 12,
    aralik: 12,
  };

  const lines = t
    .split(/\r?\n/)
    .map((x) => x.trim())
    .filter((x) => x);

  const isValid = (y, m, d) => y >= 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    let bestInLine = null;

    for (const m of line.matchAll(/\b(\d{4})-(\d{2})-(\d{2})\b/g)) {
      const y = Number.parseInt(m[1], 10);
      const mo = Number.parseInt(m[2], 10);
      const d = Number.parseInt(m[3], 10);
      if (!isValid(y, mo, d)) continue;
      const idx = typeof m.index === 'number' ? m.index : 0;
      if (bestInLine == null || idx < bestInLine.idx) {
        bestInLine = { idx, dateStr: _toDateString(y, mo, d) };
      }
    }

    for (const m of line.matchAll(/\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b/g)) {
      const d = Number.parseInt(m[1], 10);
      const mo = Number.parseInt(m[2], 10);
      const y = Number.parseInt(m[3], 10);
      if (!isValid(y, mo, d)) continue;
      const idx = typeof m.index === 'number' ? m.index : 0;
      if (bestInLine == null || idx < bestInLine.idx) {
        bestInLine = { idx, dateStr: _toDateString(y, mo, d) };
      }
    }

    for (const m of line.matchAll(/\b(\d{1,2})\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)\s+(\d{4})\b/g)) {
      const d = Number.parseInt(m[1], 10);
      const key = (m[2] ?? '').toString().trim().toLowerCase();
      const y = Number.parseInt(m[3], 10);
      const mo = months[key] ?? null;
      if (!mo || !isValid(y, mo, d)) continue;
      const idx = typeof m.index === 'number' ? m.index : 0;
      if (bestInLine == null || idx < bestInLine.idx) {
        bestInLine = { idx, dateStr: _toDateString(y, mo, d) };
      }
    }

    if (bestInLine != null) {
      return bestInLine.dateStr;
    }
  }

  const norm = (s) =>
    (s ?? '')
      .toString()
      .toLowerCase()
      .replace(/[^a-z0-9ığüşöçİĞÜŞÖÇ]/gi, '');

  const scoreLine = (line, idx) => {
    const n = norm(line);
    let score = 10;
    if (idx >= 0 && idx < 12) score += 24 - idx * 2;
    if (n.includes('tarih')) score += 80;
    if (n.includes('gunsonu') || n.includes('günsonu')) score += 60;
    if (n.includes('zraporu') || n.includes('zrapor')) score += 55;
    if (n.includes('rapor')) score += 40;
    if (n.includes('batch')) score += 30;
    if (n.includes('islemtarihi') || (n.includes('islem') && n.includes('tarih'))) score += 35;
    if (/\b\d{1,2}:\d{2}\b/.test(line)) score -= 8;
    return score;
  };

  const acc = new Map();
  const add = (dateStr, score, idx) => {
    const prev = acc.get(dateStr);
    if (!prev) {
      acc.set(dateStr, { score, firstIdx: idx });
      return;
    }
    const nextScore = prev.score + score;
    const nextFirst = Math.min(prev.firstIdx, idx);
    acc.set(dateStr, { score: nextScore, firstIdx: nextFirst });
  };

  const scanLine = (line, idx) => {
    const base = scoreLine(line, idx);

    for (const m of line.matchAll(/\b(\d{4})-(\d{2})-(\d{2})\b/g)) {
      const y = Number.parseInt(m[1], 10);
      const mo = Number.parseInt(m[2], 10);
      const d = Number.parseInt(m[3], 10);
      if (!isValid(y, mo, d)) continue;
      add(_toDateString(y, mo, d), base + 6, idx);
    }

    for (const m of line.matchAll(/\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b/g)) {
      const d = Number.parseInt(m[1], 10);
      const mo = Number.parseInt(m[2], 10);
      const y = Number.parseInt(m[3], 10);
      if (!isValid(y, mo, d)) continue;
      add(_toDateString(y, mo, d), base + 4, idx);
    }

    for (const m of line.matchAll(/\b(\d{1,2})\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)\s+(\d{4})\b/g)) {
      const d = Number.parseInt(m[1], 10);
      const key = (m[2] ?? '').toString().trim().toLowerCase();
      const y = Number.parseInt(m[3], 10);
      const mo = months[key] ?? null;
      if (!mo || !isValid(y, mo, d)) continue;
      add(_toDateString(y, mo, d), base + 10, idx);
    }
  };

  for (let i = 0; i < lines.length; i++) {
    scanLine(lines[i], i);
  }

  if (acc.size) {
    let best = null;
    for (const [dateStr, meta] of acc.entries()) {
      if (
        best == null ||
        meta.score > best.meta.score ||
        (meta.score === best.meta.score && meta.firstIdx < best.meta.firstIdx) ||
        (meta.score === best.meta.score && meta.firstIdx === best.meta.firstIdx && dateStr > best.dateStr)
      ) {
        best = { dateStr, meta };
      }
    }
    return best?.dateStr ?? null;
  }

  const iso = t.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
  if (iso) {
    const y = Number.parseInt(iso[1], 10);
    const m = Number.parseInt(iso[2], 10);
    const d = Number.parseInt(iso[3], 10);
    if (isValid(y, m, d)) return _toDateString(y, m, d);
  }

  const dmy = t.match(/\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b/);
  if (dmy) {
    const d = Number.parseInt(dmy[1], 10);
    const m = Number.parseInt(dmy[2], 10);
    const y = Number.parseInt(dmy[3], 10);
    if (isValid(y, m, d)) return _toDateString(y, m, d);
  }

  const tr = t.match(/\b(\d{1,2})\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)\s+(\d{4})\b/);
  if (tr) {
    const d = Number.parseInt(tr[1], 10);
    const key = (tr[2] ?? '').toString().trim().toLowerCase();
    const y = Number.parseInt(tr[3], 10);
    const m = months[key] ?? null;
    if (m && isValid(y, m, d)) return _toDateString(y, m, d);
  }

  return null;
}

function _extractLineValue(text, keys) {
  const lines = (text ?? '')
    .toString()
    .split(/\r?\n/)
    .map((x) => x.trim())
    .filter((x) => x);
  for (const line of lines) {
    const lower = line.toLowerCase();
    if (keys.some((k) => lower.includes(k))) {
      return line;
    }
  }
  return null;
}

function _extractLabelValue(text, regex) {
  const m = (text ?? '').toString().match(regex);
  if (!m) return null;
  const v = (m[1] ?? '').toString().trim();
  return v || null;
}

function _extractMoneyFromLine(line) {
  if (!line) return 0;
  const matches = line.match(/\d{1,3}(?:[.\s]\d{3})*(?:,\d{1,2})|\d+(?:,\d{1,2})?/g) ?? [];
  const nums = matches.map(_parseMoneyLoose).filter((n) => Number.isFinite(n));
  if (!nums.length) return 0;
  return Math.max(...nums);
}

function _parseEndOfDayFromOcr(text) {
  const reportDate = _parseOcrDate(text);

  const lines = (text ?? '')
    .toString()
    .split(/\r?\n/)
    .map((x) => x.trim())
    .filter((x) => x);
  const norm = (s) => (s ?? '').toString().toLowerCase().replace(/[^a-z0-9ığüşöçİĞÜŞÖÇ]/gi, '');
  const afterSep = (line) => {
    const m = (line ?? '').toString().match(/[:\-]\s*(.+)$/);
    const v = (m?.[1] ?? '').toString().trim();
    return v || null;
  };
  const extractIdToken = (s) => {
    const m = (s ?? '').toString().match(/\b([A-Za-z0-9][A-Za-z0-9\-\/]{2,})\b/);
    const v = (m?.[1] ?? '').toString().trim();
    return v || null;
  };
  const valueFromLabelLine = (idx, labelRe) => {
    const raw = lines[idx] ?? '';
    const viaSep = afterSep(raw);
    if (viaSep) return viaSep;
    const m = raw.match(labelRe);
    if (m && typeof m.index === 'number') {
      const tail = raw.slice(m.index + m[0].length).replace(/^[:\-\s]+/, '').trim();
      if (tail) return tail;
    }
    const next = lines[idx + 1] ?? null;
    if (next) {
      const nextTrim = next.trim();
      if (nextTrim && nextTrim.length >= 2) return nextTrim;
    }
    return null;
  };

  let merchantTitle =
    _extractLabelValue(text, /ünvan(?:ı|i)?\s*[:\-]?\s*([^\n\r]+)/i) ??
    _extractLabelValue(text, /unvan\s*[:\-]?\s*([^\n\r]+)/i) ??
    _extractLabelValue(text, /iş\s*yeri\s*(?:adı|unvan(?:ı|i)?)\s*[:\-]?\s*([^\n\r]+)/i) ??
    _extractLabelValue(text, /isy\s*yeri\s*(?:adi|unvan(?:i)?)\s*[:\-]?\s*([^\n\r]+)/i) ??
    _extractLabelValue(text, /merchant\s*(?:name|title)\s*[:\-]?\s*([^\n\r]+)/i) ??
    null;

  let workplaceNo =
    _extractLabelValue(text, /iş\s*yeri\s*(?:no|nr)\s*[:\-]?\s*([A-Za-z0-9\-\/]+)/i) ??
    _extractLabelValue(text, /isy\s*yeri\s*(?:no|nr)\s*[:\-]?\s*([A-Za-z0-9\-\/]+)/i) ??
    _extractLabelValue(text, /merchant\s*(?:no|id)\s*[:\-]?\s*([A-Za-z0-9\-\/]+)/i) ??
    null;

  let terminalNo =
    _extractLabelValue(text, /terminal\s*(?:no|nr|id)\s*[:\-]?\s*([A-Za-z0-9\-\/]+)/i) ??
    _extractLabelValue(text, /term\s*(?:no|nr|id)\s*[:\-]?\s*([A-Za-z0-9\-\/]+)/i) ??
    _extractLabelValue(text, /\btid\s*[:\-]?\s*([A-Za-z0-9\-\/]+)/i) ??
    null;

  if (!merchantTitle) {
    for (let i = 0; i < lines.length; i++) {
      const n = norm(lines[i]);
      const isLabel =
        n.includes('unvan') ||
        n.includes('ünvan') ||
        n.includes('isyeriadi') ||
        n.includes('işyeriadi') ||
        n.includes('isyeriunvani') ||
        n.includes('işyeriünvani') ||
        n.includes('işyeriunvani');
      if (!isLabel) continue;
      const v = valueFromLabelLine(i, /(ünvan(?:ı|i)?|unvan|iş\s*yeri\s*(?:adı|unvan(?:ı|i)?)|isy\s*yeri\s*(?:adi|unvan(?:i)?))/i);
      if (v) {
        merchantTitle = v;
        break;
      }
    }
  }

  if (!workplaceNo) {
    for (let i = 0; i < lines.length; i++) {
      const n = norm(lines[i]);
      const isLabel =
        n.includes('işyeri') ||
        n.includes('isyeri') ||
        n.includes('merchant') ||
        n.includes('isyerino') ||
        n.includes('işyerino');
      if (!isLabel) continue;
      const rawV = valueFromLabelLine(i, /(iş\s*yeri|isy\s*yeri|merchant)\s*(?:no|nr|id)?/i);
      const token = extractIdToken(rawV);
      if (token) {
        workplaceNo = token;
        break;
      }
    }
  }

  if (!terminalNo) {
    for (let i = 0; i < lines.length; i++) {
      const n = norm(lines[i]);
      const isLabel =
        n.includes('terminal') ||
        n.includes('termno') ||
        n.includes('terminalno') ||
        n.includes('tid');
      if (!isLabel) continue;
      const rawV = valueFromLabelLine(i, /(terminal|term|tid)\s*(?:no|nr|id)?/i);
      const token = extractIdToken(rawV);
      if (token) {
        terminalNo = token;
        break;
      }
    }
  }

  const findLineIndex = (pred) => {
    for (let i = 0; i < lines.length; i++) {
      if (pred(lines[i], i)) return i;
    }
    return -1;
  };
  const moneyAround = (startIdx, lookahead) => {
    const nums = [];
    for (let i = startIdx; i < Math.min(lines.length, startIdx + lookahead); i++) {
      const v = _extractMoneyFromLine(lines[i]);
      if (v > 0) nums.push(v);
    }
    if (!nums.length) return 0;
    return Math.max(...nums);
  };

  let fastTotal = 0;
  for (let i = 0; i < lines.length; i++) {
    const n = norm(lines[i]);
    if (!n.includes('fast')) continue;
    const v = _extractMoneyFromLine(lines[i]);
    if (v > 0) {
      fastTotal += v;
      continue;
    }
    if (i + 1 < lines.length) {
      const nextV = _extractMoneyFromLine(lines[i + 1]);
      if (nextV > 0) fastTotal += nextV;
    }
  }

  const genelIdx = findLineIndex((l) => norm(l).includes('geneltoplam'));
  const genelTotal = genelIdx >= 0 ? moneyAround(genelIdx, 2) : 0;

  const krediIdx = findLineIndex((l) => norm(l).includes('kredikartiislemleri') || (norm(l).includes('kredikarti') && norm(l).includes('islemleri')));
  const krediTotal = krediIdx >= 0 ? moneyAround(krediIdx, 8) : 0;

  const debitIdx = findLineIndex((l) => norm(l).includes('debitkartiislemleri') || (norm(l).includes('debitkarti') && norm(l).includes('islemleri')));
  const debitTotal = debitIdx >= 0 ? moneyAround(debitIdx, 8) : 0;

  const cardLine = _extractLineValue(text, ['kredi kart', 'kredi', 'kart', 'credit card', 'credit', 'card', 'genel toplam']);
  const fallbackCard = _extractMoneyFromLine(cardLine);

  const candidates = [genelTotal, krediTotal + debitTotal, krediTotal, fallbackCard].filter((x) => Number.isFinite(x) && x > 0);
  const cardTotal = candidates.length ? Math.max(...candidates) : 0;

  return { reportDate, merchantTitle, workplaceNo, terminalNo, cardTotal, fastTotal };
}

function _registerCodeFromKasa(kasa) {
  const raw = (kasa ?? '').toString().trim();
  if (!raw) return '';
  const n = Number.parseInt(raw, 10);
  if (Number.isFinite(n) && !Number.isNaN(n)) {
    return `KASA-${String(n).padStart(2, '0')}`;
  }
  return raw;
}

function _kasaNoFromRegisterCode(code) {
  if (!code) return null;
  const s = code.toString().trim();
  const m = s.match(/(\d+)/);
  if (!m) return null;
  const n = Number.parseInt(m[1], 10);
  return Number.isFinite(n) ? n : null;
}

async function _getAssignedKasaNos(branchId) {
  try {
    const rows = await queryAll(
      `
      select cr.code
      from branch_cash_registers bcr
      join cash_registers cr on cr.id = bcr.cash_register_id
      where bcr.branch_id = $1::uuid and cr.is_active = true
      order by cr.code asc
      `,
      [branchId],
    );
    const nums = (rows ?? [])
      .map((r) => _kasaNoFromRegisterCode(r.code))
      .filter((n) => Number.isFinite(n));
    return Array.from(new Set(nums));
  } catch {
    return [];
  }
}

async function getBranchDataSourceConfig(branchId) {
  const secret = integrationSecretOrNull();
  if (!secret) {
    const e = new Error('INTEGRATION_SECRET_REQUIRED');
    e.code = 'INTEGRATION_SECRET_REQUIRED';
    throw e;
  }
  const row = await queryOne(
    `
    select
      db_host as host,
      db_port as port,
      db_name as "database",
      db_user as username,
      pgp_sym_decrypt(db_password_enc, $2::text)::text as password,
      db_ssl as ssl,
      is_active as "isActive"
    from branch_data_sources
    where branch_id = $1::uuid
    limit 1
    `,
    [branchId, secret],
  );
  if (!row) return null;
  return row;
}

app.get(
  '/branch-data-sources',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const rows = await queryAll(
      `
      select
        b.id as "branchId",
        b.code as "branchCode",
        b.name as "branchName",
        d.db_host as host,
        d.db_port as port,
        d.db_name as "database",
        d.db_user as username,
        d.db_ssl as ssl,
        d.is_active as "isActive",
        d.updated_at as "updatedAt"
      from branches b
      left join branch_data_sources d on d.branch_id = b.id
      order by b.name asc
      `,
      [],
    );
    res.json(rows);
  }),
);

app.put(
  '/branch-data-sources/:branchId',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const secret = integrationSecretOrNull();
    if (!secret) return res.status(503).json({ error: 'INTEGRATION_SECRET_REQUIRED' });

    const branchId = (req.params.branchId ?? '').toString().trim();
    const host = (req.body?.host ?? '').toString().trim();
    const portRaw = req.body?.port;
    const port = Number.isFinite(portRaw) ? Number(portRaw) : Number((portRaw ?? '').toString().trim() || 5432);
    const database = (req.body?.database ?? req.body?.dbName ?? '').toString().trim();
    const username = (req.body?.username ?? req.body?.user ?? '').toString().trim();
    const hasPassword = Object.prototype.hasOwnProperty.call(req.body ?? {}, 'password');
    const passwordRaw = (req.body?.password ?? '').toString();
    const password = passwordRaw.length ? passwordRaw : null;
    const sslRaw = req.body?.ssl;
    const ssl = typeof sslRaw === 'boolean' ? sslRaw : false;
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : true;

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!host) return res.status(400).json({ error: 'HOST_REQUIRED' });
    if (!Number.isFinite(port) || port <= 0) return res.status(400).json({ error: 'PORT_REQUIRED' });
    if (!database) return res.status(400).json({ error: 'DATABASE_REQUIRED' });
    if (!username) return res.status(400).json({ error: 'USERNAME_REQUIRED' });

    await pool.query(
      `
      insert into branch_data_sources(
        branch_id, db_host, db_port, db_name, db_user, db_password_enc, db_ssl, is_active
      )
      values (
        $1::uuid,
        $2,
        $3::int,
        $4,
        $5,
        case
          when $6::boolean then pgp_sym_encrypt($7::text, $8::text)
          else null
        end,
        $9::boolean,
        $10::boolean
      )
      on conflict (branch_id)
      do update set
        db_host = excluded.db_host,
        db_port = excluded.db_port,
        db_name = excluded.db_name,
        db_user = excluded.db_user,
        db_password_enc = case
          when $6::boolean then pgp_sym_encrypt($7::text, $8::text)
          else branch_data_sources.db_password_enc
        end,
        db_ssl = excluded.db_ssl,
        is_active = excluded.is_active,
        updated_at = now()
      `,
      [branchId, host, port, database, username, hasPassword, password ?? '', secret, ssl, isActive],
    );

    res.json({ ok: true });
  }),
);

app.post(
  '/branch-data-sources/:branchId/test',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const branchId = (req.params.branchId ?? '').toString().trim();
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    let row;
    try {
      row = await getBranchDataSourceConfig(branchId);
    } catch (e) {
      const code = (e?.code ?? '').toString();
      const message = (e?.message ?? 'CONFIG_ERROR').toString();
      return res.status(200).json({
        ok: false,
        error: code || 'CONFIG_ERROR',
        message,
      });
    }
    if (!row) return res.status(404).json({ ok: false, error: 'NOT_FOUND' });
    if (!row.isActive) return res.status(400).json({ ok: false, error: 'INACTIVE' });

    const ssl = row.ssl ? { rejectUnauthorized: false } : false;
    const branchPool = new pg.Pool({
      host: row.host,
      port: Number(row.port),
      user: row.username,
      password: row.password ?? '',
      database: row.database,
      max: 1,
      idleTimeoutMillis: 5_000,
      connectionTimeoutMillis: 8_000,
      ssl,
    });
    try {
      const r = await branchPool.query('select 1 as ok');
      return res.json({ ok: r.rows?.[0]?.ok === 1 });
    } catch (e) {
      const code = (e?.code ?? '').toString();
      const message = (e?.message ?? 'CONNECTION_FAILED').toString();
      return res.status(200).json({
        ok: false,
        error: code || 'CONNECTION_FAILED',
        message,
        host: row.host,
        port: Number(row.port),
        database: row.database,
        username: row.username,
      });
    } finally {
      await branchPool.end();
    }
  }),
);

app.get(
  '/pos/live/daily-total',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    const businessDate = asDateString(req.query?.businessDate ?? req.query?.date);
    const businessDayStartHourRaw = req.query?.businessDayStartHour ?? 0;
    let businessDayStartHour = Number.parseInt((businessDayStartHourRaw ?? 0).toString(), 10);
    if (!Number.isFinite(businessDayStartHour)) businessDayStartHour = 0;
    if (businessDayStartHour < 0 || businessDayStartHour > 23) businessDayStartHour = 0;

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!businessDate) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const cfg = await getBranchDataSourceConfig(branchId);
    if (!cfg) return res.status(404).json({ error: 'BRANCH_DB_NOT_CONFIGURED' });
    if (!cfg.isActive) return res.status(400).json({ error: 'BRANCH_DB_INACTIVE' });

    const registerCodeRaw = (req.query?.registerCode ?? '').toString().trim();
    const registerCode = registerCodeRaw ? registerCodeRaw : null;
    const assignedKasaNos = await _getAssignedKasaNos(branchId);
    const kasaNos =
      registerCode ? [_kasaNoFromRegisterCode(registerCode)].filter((x) => x != null) : (assignedKasaNos.length ? assignedKasaNos : null);

    const ssl = cfg.ssl ? { rejectUnauthorized: false } : false;
    const branchPool = new pg.Pool({
      host: cfg.host,
      port: Number(cfg.port ?? 5432),
      user: cfg.username,
      password: (cfg.password ?? '').toString(),
      database: cfg.database,
      max: 1,
      idleTimeoutMillis: 8_000,
      connectionTimeoutMillis: 12_000,
      ssl,
    });

    try {
      let total = 0;
      try {
        const r = await branchPool.query(
          `
          select
            coalesce(sum(coalesce(otutar,0)+coalesce(iskonto,0)),0) as gross_total
          from ads_odeme
          where (raptar - ($2::int * interval '1 hour'))::date = $1::date
          ${kasaNos && kasaNos.length ? 'and kasa = any($3::int[])' : ''}
          `,
          kasaNos && kasaNos.length
            ? [businessDate, businessDayStartHour, kasaNos]
            : [businessDate, businessDayStartHour],
        );
        total = _parseMoneyLoose(r.rows?.[0]?.gross_total);
      } catch {}

      if (!total) {
        try {
          const r = await branchPool.query(
            `
            select coalesce(sum(coalesce(toplam,0)),0) as total
            from kasa_raporu
            where (tarih::timestamp - ($2::int * interval '1 hour'))::date = $1::date
            ${kasaNos && kasaNos.length ? 'and kasa = any($3::int[])' : ''}
            `,
            kasaNos && kasaNos.length
              ? [businessDate, businessDayStartHour, kasaNos]
              : [businessDate, businessDayStartHour],
          );
          total = _parseMoneyLoose(r.rows?.[0]?.total);
        } catch {}
      }

      res.json({
        branchId,
        businessDate,
        registerCode,
        grossTotal: Number.isFinite(total) ? total : 0,
      });
    } finally {
      await branchPool.end();
    }
  }),
);

app.post(
  '/pos/pull/branch-daily',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = (req.body?.branchId ?? '').toString().trim();
    const businessDate = asDateString(req.body?.businessDate ?? req.body?.date);
    const source = (req.body?.source ?? 'pos').toString().trim() || 'pos';
    const businessDayStartHourRaw =
      req.body?.businessDayStartHour ?? req.body?.dayStartHour ?? 0;
    let businessDayStartHour = Number.parseInt(
      (businessDayStartHourRaw ?? 0).toString(),
      10,
    );
    if (!Number.isFinite(businessDayStartHour)) businessDayStartHour = 0;
    if (businessDayStartHour < 0 || businessDayStartHour > 23) {
      businessDayStartHour = 0;
    }

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!businessDate) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });
    if (source !== 'pos') return res.status(400).json({ error: 'INVALID_SOURCE' });

    const cfg = await getBranchDataSourceConfig(branchId);
    if (!cfg) return res.status(404).json({ error: 'BRANCH_DB_NOT_CONFIGURED' });
    if (!cfg.isActive) return res.status(400).json({ error: 'BRANCH_DB_INACTIVE' });
    const out = await pullBranchDailyPos({
      branchId,
      businessDate,
      source,
      businessDayStartHour,
      cfg,
    });
    res.json(out);
  }),
);

async function pullBranchDailyPos({ branchId, businessDate, source, businessDayStartHour, cfg }) {
  const ssl = cfg.ssl ? { rejectUnauthorized: false } : false;
  const branchPool = new pg.Pool({
    host: cfg.host,
    port: Number(cfg.port ?? 5432),
    user: cfg.username,
    password: (cfg.password ?? '').toString(),
    database: cfg.database,
    max: 1,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 12_000,
    ssl,
  });

  let kasaList = [];
  const salesByKasa = new Map();
  const paymentsAgg = [];
  const productsAgg = [];
  const adjustmentsAgg = [];
  const groupsAgg = [];
  const assignedKasaNos = await _getAssignedKasaNos(branchId);
  const assignedKasaNosParam = assignedKasaNos.length ? assignedKasaNos : null;
  try {
    try {
      const r = await branchPool.query(
        `
          select
            kasa,
            coalesce(sum(coalesce(otutar,0)+coalesce(iskonto,0)),0) as gross_total
          from ads_odeme
          where (raptar - ($2::int * interval '1 hour'))::date = $1::date
            and ($3::int[] is null or kasa = any($3::int[]))
          group by kasa
          order by kasa asc
          `,
        [businessDate, businessDayStartHour, assignedKasaNosParam],
      );
      for (const row of r.rows ?? []) {
        const kasa = row.kasa;
        const registerCode = _registerCodeFromKasa(kasa);
        if (!registerCode) continue;
        const val = _parseMoneyLoose(row.gross_total);
        salesByKasa.set(registerCode, (salesByKasa.get(registerCode) ?? 0) + val);
      }
    } catch {}

    if (!salesByKasa.size) {
      try {
        const r = await branchPool.query(
          `
            select kasa, toplam, z_tutar, ykt
            from kasa_raporu
            where (tarih::timestamp - ($2::int * interval '1 hour'))::date = $1::date
              and ($3::int[] is null or kasa = any($3::int[]))
            `,
          [businessDate, businessDayStartHour, assignedKasaNosParam],
        );
        for (const row of r.rows ?? []) {
          const kasa = row.kasa;
          const registerCode = _registerCodeFromKasa(kasa);
          if (!registerCode) continue;
          const candidates = [
            _parseMoneyLoose(row.toplam),
            _parseMoneyLoose(row.z_tutar),
            _parseMoneyLoose(row.ykt),
          ];
          const val = candidates.find((n) => n > 0) ?? candidates.find((n) => n !== 0) ?? 0;
          salesByKasa.set(registerCode, (salesByKasa.get(registerCode) ?? 0) + val);
        }
      } catch {}
    }

    if (!salesByKasa.size) {
      try {
        const r = await branchPool.query(
          `
            select
              kasa,
              coalesce(sum(coalesce(tutar,0)),0) as gross_total
            from ads_adisyon
            where
              (raptar - ($2::int * interval '1 hour'))::date = $1::date
              and coalesce(sturu,0) not in (1,2,4)
              and ($3::int[] is null or kasa = any($3::int[]))
            group by kasa
            order by kasa asc
            `,
          [businessDate, businessDayStartHour, assignedKasaNosParam],
        );
        for (const row of r.rows ?? []) {
          const kasa = row.kasa;
          const registerCode = _registerCodeFromKasa(kasa);
          if (!registerCode) continue;
          const val = _parseMoneyLoose(row.gross_total);
          salesByKasa.set(registerCode, (salesByKasa.get(registerCode) ?? 0) + val);
        }
      } catch {}
    }

    if (salesByKasa.size) {
      kasaList = [...salesByKasa.keys()]
        .map((code) => {
          const n = Number.parseInt(code.replace('KASA-', ''), 10);
          return Number.isFinite(n) ? n : null;
        })
        .filter((x) => x != null);
    } else {
      try {
        const r = await branchPool.query(
          `
            select distinct kasa
            from ads_odeme
            where (raptar - ($2::int * interval '1 hour'))::date = $1::date
              and ($3::int[] is null or kasa = any($3::int[]))
            order by kasa asc
            `,
          [businessDate, businessDayStartHour, assignedKasaNosParam],
        );
        kasaList = (r.rows ?? [])
          .map((x) => Number.parseInt((x.kasa ?? '').toString(), 10))
          .filter((n) => Number.isFinite(n));
      } catch {}
    }

    const kasaNos = assignedKasaNos.length ? assignedKasaNos : (kasaList.length ? kasaList : null);

    if (kasaNos) {
      try {
        const r = await branchPool.query(
          `
            select
              kasa,
              coalesce(sum(coalesce(iskonto,0)),0) as total,
              coalesce(count(distinct case when coalesce(iskonto,0) > 0 then adsno end),0)::int as count
            from ads_odeme
            where (raptar - ($2::int * interval '1 hour'))::date = $1::date and kasa = any($3)
            group by kasa
            order by kasa asc
            `,
          [businessDate, businessDayStartHour, kasaNos],
        );
        for (const row of r.rows ?? []) {
          const registerCode = _registerCodeFromKasa(row.kasa);
          if (!registerCode) continue;
          adjustmentsAgg.push({
            registerCode,
            kind: 'discount',
            amount: _parseMoneyLoose(row.total),
            count: Number.parseInt((row.count ?? 0).toString(), 10) || 0,
          });
        }
      } catch {}

      try {
        const r = await branchPool.query(
          `
            select
              kasa,
              coalesce(adtur, 0) as adtur,
              count(distinct adsno)::int as order_count,
              coalesce(sum(coalesce(otutar,0)+coalesce(iskonto,0)),0) as gross_total
            from ads_odeme
            where (raptar - ($2::int * interval '1 hour'))::date = $1::date and kasa = any($3)
            group by kasa, coalesce(adtur, 0)
            order by kasa asc, coalesce(adtur, 0) asc
            `,
          [businessDate, businessDayStartHour, kasaNos],
        );
        for (const row of r.rows ?? []) {
          const registerCode = _registerCodeFromKasa(row.kasa);
          if (!registerCode) continue;
          const adtur = Number.parseInt((row.adtur ?? 0).toString(), 10) || 0;
          const groupCode = adtur === 1 ? 'paket' : adtur === 3 ? 'hizli' : 'adisyon';
          groupsAgg.push({
            registerCode,
            groupCode,
            orderCount: Number.parseInt((row.order_count ?? 0).toString(), 10) || 0,
            grossTotal: _parseMoneyLoose(row.gross_total),
          });
        }
      } catch {}

      try {
        const r = await branchPool.query(
          `
            select
              kasa,
              sturu,
              coalesce(sum(coalesce(tutar,0)),0) as total,
              coalesce(count(*),0)::int as count
            from ads_adisyon
            where (raptar - ($2::int * interval '1 hour'))::date = $1::date and kasa = any($3) and sturu in (1,2,4)
            group by kasa, sturu
            order by kasa asc, sturu asc
            `,
          [businessDate, businessDayStartHour, kasaNos],
        );
        for (const row of r.rows ?? []) {
          const registerCode = _registerCodeFromKasa(row.kasa);
          if (!registerCode) continue;
          const sturu = Number.parseInt((row.sturu ?? 0).toString(), 10) || 0;
          const kind =
            sturu === 1 ? 'comp' : sturu === 2 ? 'refund' : sturu === 4 ? 'cancel' : null;
          if (!kind) continue;
          adjustmentsAgg.push({
            registerCode,
            kind,
            amount: _parseMoneyLoose(row.total),
            count: Number.parseInt((row.count ?? 0).toString(), 10) || 0,
          });
        }
      } catch {}

      try {
        const r = await branchPool.query(
          `
            with per_ads as (
              select
                h.kasano as kasa,
                h.ads_no,
                max(coalesce(h.borcu,0)) as borc
              from ads_hareket h
              where (h.islem_zamani - ($2::int * interval '1 hour'))::date = $1::date and h.kasano = any($3)
              group by h.kasano, h.ads_no
            )
            select
              kasa,
              coalesce(sum(case when borc > 0 then borc else 0 end),0) as total,
              coalesce(count(case when borc > 0 then 1 end),0)::int as count
            from per_ads
            group by kasa
            order by kasa asc
            `,
          [businessDate, businessDayStartHour, kasaNos],
        );
        for (const row of r.rows ?? []) {
          const registerCode = _registerCodeFromKasa(row.kasa);
          if (!registerCode) continue;
          adjustmentsAgg.push({
            registerCode,
            kind: 'debt',
            amount: _parseMoneyLoose(row.total),
            count: Number.parseInt((row.count ?? 0).toString(), 10) || 0,
          });
        }
      } catch {}

      try {
        const r = await branchPool.query(
          `
            select
              kasa,
              coalesce(otip, 0) as otip,
              coalesce(sum(coalesce(otutar,0)),0) as total
            from ads_odeme
            where (raptar - ($2::int * interval '1 hour'))::date = $1::date and kasa = any($3)
            group by kasa, coalesce(otip, 0)
            order by kasa asc, otip asc
            `,
          [businessDate, businessDayStartHour, kasaNos],
        );
        for (const row of r.rows ?? []) {
          const registerCode = _registerCodeFromKasa(row.kasa);
          if (!registerCode) continue;
          const paymentCode = (row.otip ?? 0).toString();
          paymentsAgg.push({
            registerCode,
            paymentCode,
            amount: _parseMoneyLoose(row.total),
          });
        }
      } catch {}

      try {
        const r = await branchPool.query(
          `
            select
              a.kasa,
              a.pluid,
              coalesce(sum(coalesce(a.miktar,0)),0) as quantity,
              coalesce(sum(coalesce(a.tutar,0)),0) as total,
              max(coalesce(p.product_name,'')) as product_name
            from ads_adisyon a
            left join product p on a.pluid = p.plu
            where (a.raptar - ($2::int * interval '1 hour'))::date = $1::date and a.kasa = any($3) and a.pluid is not null
            group by a.kasa, a.pluid
            order by coalesce(sum(coalesce(a.tutar,0)),0) desc
            limit 500
            `,
          [businessDate, businessDayStartHour, kasaNos],
        );
        for (const row of r.rows ?? []) {
          const registerCode = _registerCodeFromKasa(row.kasa);
          if (!registerCode) continue;
          const productCode = (row.pluid ?? '').toString();
          if (!productCode) continue;
          const productName = (row.product_name ?? '').toString().trim() || null;
          productsAgg.push({
            registerCode,
            productCode,
            productName,
            quantity: _parseMoneyLoose(row.quantity),
            grossTotal: _parseMoneyLoose(row.total),
          });
        }
      } catch {}
    }
  } finally {
    await branchPool.end();
  }

  const client = await pool.connect();
  try {
    await client.query('begin');

    await client.query(
      `delete from pos_register_daily_sales where branch_id=$1::uuid and business_date=$2::date and source=$3`,
      [branchId, businessDate, source],
    );
    await client.query(
      `delete from pos_register_daily_payments where branch_id=$1::uuid and business_date=$2::date and source=$3`,
      [branchId, businessDate, source],
    );
    await client.query(
      `delete from pos_register_daily_product_sales where branch_id=$1::uuid and business_date=$2::date and source=$3`,
      [branchId, businessDate, source],
    );
    await client.query(
      `delete from pos_register_daily_adjustments where branch_id=$1::uuid and business_date=$2::date and source=$3`,
      [branchId, businessDate, source],
    );
    await client.query(
      `delete from pos_register_daily_sales_groups where branch_id=$1::uuid and business_date=$2::date and source=$3`,
      [branchId, businessDate, source],
    );

    let salesUpserts = 0;
    for (const [registerCode, grossTotal] of salesByKasa.entries()) {
      await client.query(
        `
          insert into pos_register_daily_sales(branch_id, business_date, register_code, gross_total, source)
          values ($1::uuid, $2::date, $3, $4::numeric, $5)
          on conflict (branch_id, business_date, source, register_code)
          do update set gross_total=excluded.gross_total, updated_at=now()
          `,
        [branchId, businessDate, registerCode, grossTotal, source],
      );
      salesUpserts++;
    }

    let paymentUpserts = 0;
    for (const p of paymentsAgg) {
      await client.query(
        `
          insert into pos_register_daily_payments(
            branch_id, business_date, register_code, payment_code, amount, source
          )
          values ($1::uuid, $2::date, $3, $4, $5::numeric, $6)
          on conflict (branch_id, business_date, source, register_code, payment_code)
          do update set amount=excluded.amount, updated_at=now()
          `,
        [branchId, businessDate, p.registerCode, p.paymentCode, p.amount, source],
      );
      paymentUpserts++;
    }

    let productUpserts = 0;
    for (const pr of productsAgg) {
      if (pr.productName) {
        await client.query(
          `
            insert into inv_products(code, name, unit, is_active)
            values ($1, $2, 'adet', true)
            on conflict (code) do update set
              name = excluded.name,
              is_active = true,
              updated_at = now()
            `,
          [pr.productCode, pr.productName],
        );
      }
      await client.query(
        `
          insert into pos_register_daily_product_sales(
            branch_id, business_date, register_code, product_code, product_name, quantity, gross_total, source
          )
          values ($1::uuid, $2::date, $3, $4, $5, $6::numeric, $7::numeric, $8)
          on conflict (branch_id, business_date, source, register_code, product_code)
          do update set
            product_name = excluded.product_name,
            quantity = excluded.quantity,
            gross_total = excluded.gross_total,
            updated_at = now()
          `,
        [
          branchId,
          businessDate,
          pr.registerCode,
          pr.productCode,
          pr.productName,
          pr.quantity,
          pr.grossTotal,
          source,
        ],
      );
      productUpserts++;
    }

    let adjustmentUpserts = 0;
    for (const a of adjustmentsAgg) {
      await client.query(
        `
          insert into pos_register_daily_adjustments(
            branch_id, business_date, register_code, kind, amount, count, source
          )
          values ($1::uuid, $2::date, $3, $4, $5::numeric, $6::int, $7)
          on conflict (branch_id, business_date, source, register_code, kind)
          do update set
            amount = excluded.amount,
            count = excluded.count,
            updated_at = now()
          `,
        [branchId, businessDate, a.registerCode, a.kind, a.amount, a.count, source],
      );
      adjustmentUpserts++;
    }

    let groupUpserts = 0;
    for (const g of groupsAgg) {
      await client.query(
        `
          insert into pos_register_daily_sales_groups(
            branch_id, business_date, register_code, group_code, order_count, gross_total, source
          )
          values ($1::uuid, $2::date, $3, $4, $5::int, $6::numeric, $7)
          on conflict (branch_id, business_date, source, register_code, group_code)
          do update set
            order_count = excluded.order_count,
            gross_total = excluded.gross_total,
            updated_at = now()
          `,
        [branchId, businessDate, g.registerCode, g.groupCode, g.orderCount, g.grossTotal, source],
      );
      groupUpserts++;
    }

    const sumRow = await client.query(
      `
        select coalesce(sum(gross_total),0) as total
        from pos_register_daily_sales
        where branch_id=$1::uuid and business_date=$2::date and source=$3
        `,
      [branchId, businessDate, source],
    );
    const total = sumRow.rows?.[0]?.total ?? 0;
    await client.query(
      `
        insert into daily_sales(branch_id, business_date, source, gross_total)
        values ($1::uuid, $2::date, $3, $4::numeric)
        on conflict (branch_id, business_date, source)
        do update set gross_total=excluded.gross_total
        `,
      [branchId, businessDate, source, total],
    );

    await client.query('commit');
    return {
      ok: true,
      branchId,
      businessDate,
      salesUpserts,
      paymentUpserts,
      productUpserts,
      adjustmentUpserts,
      groupUpserts,
      dailyTotal: total,
    };
  } catch (e) {
    await client.query('rollback');
    throw e;
  } finally {
    client.release();
  }
}

app.get(
  '/cron/pos/pull',
  cronJobAuthRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchIdFilter = (req.query?.branchId ?? '').toString().trim() || null;
    const today = istanbulDateString(0);
    const yesterday = istanbulDateString(-1);
    const automationUserId = await getAutomationUserId();
    if (!automationUserId) return res.status(503).json({ error: 'NO_AUTOMATION_USER' });

    const branches = await queryAll(
      `
      select id, business_day_start_hour as "businessDayStartHour"
      from branches
      where is_active = true
      ${branchIdFilter ? 'and id = $1::uuid' : ''}
      order by name asc
      `,
      branchIdFilter ? [branchIdFilter] : [],
    );

    const pulledYesterdayRows = await queryAll(
      `
      select branch_id
      from daily_sales
      where business_date = $1::date and source = 'pos'
      `,
      [yesterday],
    );
    const pulledYesterday = new Set(pulledYesterdayRows.map((r) => r.branch_id));

    const results = await mapLimit(branches, 2, async (b) => {
      const branchId = (b.id ?? '').toString();
      const businessDayStartHour =
        Number.parseInt((b.businessDayStartHour ?? 0).toString(), 10) || 0;

      const r = {
        branchId,
        ok: true,
        pulled: [],
        reconciliation: null,
        errors: [],
      };

      let cfg = null;
      try {
        cfg = await getBranchDataSourceConfig(branchId);
      } catch (e) {
        r.ok = false;
        r.errors.push({
          step: 'config',
          error: (e?.code ?? 'CONFIG_ERROR').toString(),
          message: (e?.message ?? 'CONFIG_ERROR').toString(),
        });
        return r;
      }

      if (!cfg) {
        r.ok = false;
        r.errors.push({ step: 'config', error: 'BRANCH_DB_NOT_CONFIGURED' });
        return r;
      }
      if (!cfg.isActive) {
        r.ok = false;
        r.errors.push({ step: 'config', error: 'BRANCH_DB_INACTIVE' });
        return r;
      }

      const source = 'pos';

      const needYesterday = !pulledYesterday.has(branchId);
      if (needYesterday) {
        try {
          const out = await pullBranchDailyPos({
            branchId,
            businessDate: yesterday,
            source,
            businessDayStartHour,
            cfg,
          });
          r.pulled.push({ date: yesterday, ...out });
        } catch (e) {
          r.ok = false;
          r.errors.push({
            step: 'pull',
            date: yesterday,
            error: (e?.code ?? 'PULL_FAILED').toString(),
            message: (e?.message ?? 'PULL_FAILED').toString(),
          });
        }
      }

      try {
        const out = await pullBranchDailyPos({
          branchId,
          businessDate: today,
          source,
          businessDayStartHour,
          cfg,
        });
        r.pulled.push({ date: today, ...out });
      } catch (e) {
        r.ok = false;
        r.errors.push({
          step: 'pull',
          date: today,
          error: (e?.code ?? 'PULL_FAILED').toString(),
          message: (e?.message ?? 'PULL_FAILED').toString(),
        });
      }

      try {
        const id = await ensureCashReconciliation({
          branchId,
          businessDate: today,
          createdByUserId: automationUserId,
        });
        r.reconciliation = { ok: Boolean(id), id };
        if (!id) {
          r.ok = false;
          r.errors.push({
            step: 'reconciliation',
            date: today,
            error: 'RECONCILIATION_FAILED',
            message: 'İcmal oluşturulamadı',
          });
        }
      } catch (e) {
        r.ok = false;
        r.reconciliation = { ok: false, id: null };
        r.errors.push({
          step: 'reconciliation',
          date: today,
          error: (e?.code ?? 'RECONCILIATION_FAILED').toString(),
          message: (e?.message ?? 'RECONCILIATION_FAILED').toString(),
        });
      }

      return r;
    });

    const okCount = results.filter((x) => x.ok).length;
    res.json({
      ok: true,
      today,
      yesterday,
      branches: results.length,
      okCount,
      failCount: results.length - okCount,
      results,
    });
  }),
);

app.get(
  '/pos/cancellations',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    const businessDate = asDateString(req.query?.date ?? req.query?.businessDate);
    const registerCodeRaw = (req.query?.registerCode ?? '').toString().trim();
    const registerCode = registerCodeRaw ? registerCodeRaw : null;
    const startHourRaw = req.query?.businessDayStartHour ?? 0;
    let businessDayStartHour = Number.parseInt((startHourRaw ?? 0).toString(), 10);
    if (!Number.isFinite(businessDayStartHour)) businessDayStartHour = 0;
    if (businessDayStartHour < 0 || businessDayStartHour > 23) businessDayStartHour = 0;

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!businessDate) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const cfg = await getBranchDataSourceConfig(branchId);
    if (!cfg) return res.status(404).json({ error: 'BRANCH_DB_NOT_CONFIGURED' });
    if (!cfg.isActive) return res.status(400).json({ error: 'BRANCH_DB_INACTIVE' });

    const ssl = cfg.ssl ? { rejectUnauthorized: false } : false;
    const branchPool = new pg.Pool({
      host: cfg.host,
      port: Number(cfg.port ?? 5432),
      user: cfg.username,
      password: (cfg.password ?? '').toString(),
      database: cfg.database,
      max: 1,
      idleTimeoutMillis: 10_000,
      connectionTimeoutMillis: 12_000,
      ssl,
    });

    const decodeKasaNo = (code) => {
      if (!code) return null;
      const s = code.toString().trim();
      const m = s.match(/(\d+)/);
      if (!m) return null;
      const n = Number.parseInt(m[1], 10);
      return Number.isFinite(n) ? n : null;
    };

    let kasaNos = null;
    if (registerCode) {
      const n = decodeKasaNo(registerCode);
      if (n != null) kasaNos = [n];
    }

    if (!kasaNos) {
      try {
        const r = await branchPool.query(
          `
          select distinct kasa
          from ads_adisyon
          where (raptar - ($2::int * interval '1 hour'))::date = $1::date
          order by kasa asc
          `,
          [businessDate, businessDayStartHour],
        );
        kasaNos = (r.rows ?? [])
          .map((x) => Number.parseInt((x.kasa ?? '').toString(), 10))
          .filter((n) => Number.isFinite(n));
      } catch {
        kasaNos = [];
      }
    }

    try {
      const colRows = await branchPool.query(
        `
        select column_name
        from information_schema.columns
        where table_schema='public' and table_name='ads_adisyon' and column_name = any($1::text[])
        `,
        [['ack1', 'ack2', 'ack3']],
      );
      const cols = new Set((colRows.rows ?? []).map((r) => r.column_name));
      const reasonParts = [];
      if (cols.has('ack1')) reasonParts.push(`NULLIF(TRIM(COALESCE(a.ack1::text,'')), '')`);
      if (cols.has('ack2')) reasonParts.push(`NULLIF(TRIM(COALESCE(a.ack2::text,'')), '')`);
      if (cols.has('ack3')) reasonParts.push(`NULLIF(TRIM(COALESCE(a.ack3::text,'')), '')`);
      const reasonExpr = reasonParts.length ? `COALESCE(${reasonParts.join(', ')})` : `NULL::text`;

      const r = await branchPool.query(
        `
        select
          a.kasa,
          a.adsno,
          a.pluid,
          max(coalesce(p.product_name,'')) as product_name,
          coalesce(sum(coalesce(a.miktar,0)),0) as quantity,
          coalesce(sum(coalesce(a.tutar,0)),0) as total,
          ${reasonExpr} as reason,
          max(coalesce(per.adi,'')) as cancelled_by_name,
          max(a.raptar) as occurred_at,
          max(coalesce(a.sturu,0))::int as sturu
        from ads_adisyon a
        left join product p on a.pluid = p.plu
        left join personel per on a.garsonno = per.id
        where
          (a.raptar - ($2::int * interval '1 hour'))::date = $1::date
          and a.kasa = any($3::int[])
          and a.sturu in (1,2,4)
        group by a.kasa, a.adsno, a.pluid, ${reasonExpr}
        order by max(a.raptar) desc
        limit 500
        `,
        [businessDate, businessDayStartHour, kasaNos],
      );

      const rows = (r.rows ?? []).map((row) => {
        const registerCode = _registerCodeFromKasa(row.kasa);
        const sturu = Number.parseInt((row.sturu ?? 0).toString(), 10) || 0;
        const type = sturu === 1 ? 'ikram' : sturu === 2 ? 'iade' : sturu === 4 ? 'iptal' : 'diger';
        return {
          registerCode,
          orderId: row.adsno?.toString() ?? null,
          productCode: row.pluid?.toString() ?? null,
          productName: (row.product_name ?? '').toString(),
          quantity: _parseMoneyLoose(row.quantity),
          total: _parseMoneyLoose(row.total),
          reason: row.reason?.toString() ?? null,
          cancelledByName: (row.cancelled_by_name ?? '').toString().trim() || null,
          occurredAt: row.occurred_at,
          type,
        };
      });

      res.json(rows);
    } finally {
      await branchPool.end();
    }
  }),
);

app.get(
  '/payment-types',
  authRequired,
  asyncRoute(async (req, res) => {
  const rows = await queryAll(
    `
    select id, code, name, is_active as "isActive"
    from payment_types
    order by name asc
    `,
    [],
  );
  res.json(rows);
  }),
);

app.post(
  '/payment-types',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const name = (req.body?.name ?? '').toString().trim();
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });
    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw || `${slugify(name)}-${Math.floor(Math.random() * 9000 + 1000)}`;

    const row = await queryOne(
      `
      insert into payment_types(code, name, is_active)
      values ($1, $2, true)
      on conflict (code) do update set
        name = excluded.name,
        is_active = true,
        updated_at = now()
      returning id
      `,
      [code, name],
    );

    res.json({ id: row.id });
  }),
);

app.patch(
  '/payment-types/:id',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const code = (req.body?.code ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    if (!name && !code && isActive == null) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (code) add('code = ?', code);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(
      `update payment_types set ${sets.join(', ')} where id = $1::uuid`,
      params,
    );

    res.json({ ok: true });
  }),
);

app.get(
  '/expense-types',
  authRequired,
  asyncRoute(async (req, res) => {
  const rows = await queryAll(
    `
    select id, code, name, is_active as "isActive"
    from expense_types
    order by name asc
    `,
    [],
  );
  res.json(rows);
  }),
);

app.post(
  '/expense-types',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const name = (req.body?.name ?? '').toString().trim();
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });
    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw || `${slugify(name)}-${Math.floor(Math.random() * 9000 + 1000)}`;

    const row = await queryOne(
      `
      insert into expense_types(code, name, is_active)
      values ($1, $2, true)
      on conflict (code) do update set
        name = excluded.name,
        is_active = true,
        updated_at = now()
      returning id
      `,
      [code, name],
    );

    res.json({ id: row.id });
  }),
);

app.patch(
  '/expense-types/:id',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    if (!name && isActive == null) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(
      `update expense_types set ${sets.join(', ')} where id = $1::uuid`,
      params,
    );

    res.json({ ok: true });
  }),
);

app.get(
  '/income-centers',
  authRequired,
  asyncRoute(async (req, res) => {
    const rows = await queryAll(
      `
      select id, code, name, is_active as "isActive"
      from income_centers
      order by name asc
      `,
      [],
    );
    res.json(rows);
  }),
);

app.post(
  '/income-centers',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const name = (req.body?.name ?? '').toString().trim();
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });
    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw || `${slugify(name)}-${Math.floor(Math.random() * 9000 + 1000)}`;

    const row = await queryOne(
      `
      insert into income_centers(code, name, is_active)
      values ($1, $2, true)
      on conflict (code) do update set
        name = excluded.name,
        is_active = true,
        updated_at = now()
      returning id
      `,
      [code, name],
    );

    res.json({ id: row.id });
  }),
);

app.patch(
  '/income-centers/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    if (!name && isActive == null) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(
      `update income_centers set ${sets.join(', ')} where id = $1::uuid`,
      params,
    );

    res.json({ ok: true });
  }),
);

app.get(
  '/cash-registers',
  authRequired,
  asyncRoute(async (req, res) => {
    const rows = await queryAll(
      `
      select id, code, name, is_active as "isActive"
      from cash_registers
      order by name asc
      `,
      [],
    );
    res.json(rows);
  }),
);

app.post(
  '/cash-registers',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const name = (req.body?.name ?? '').toString().trim();
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });
    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw || `${slugify(name)}-${Math.floor(Math.random() * 9000 + 1000)}`;

    const row = await queryOne(
      `
      insert into cash_registers(code, name, is_active)
      values ($1, $2, true)
      on conflict (code) do update set
        name = excluded.name,
        is_active = true,
        updated_at = now()
      returning id
      `,
      [code, name],
    );
    res.json({ id: row.id });
  }),
);

app.patch(
  '/cash-registers/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    if (!name && isActive == null) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(`update cash_registers set ${sets.join(', ')} where id = $1::uuid`, params);
    res.json({ ok: true });
  }),
);

app.get(
  '/unit-sets',
  authRequired,
  asyncRoute(async (req, res) => {
    const rows = await queryAll(
      `
      select id, code, name, is_active as "isActive"
      from unit_sets
      order by name asc
      `,
      [],
    );
    res.json(rows);
  }),
);

app.post(
  '/unit-sets',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const code = (req.body?.code ?? '').toString().trim();
    const name = (req.body?.name ?? '').toString().trim();
    if (!code) return res.status(400).json({ error: 'CODE_REQUIRED' });
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });

    const row = await queryOne(
      `
      insert into unit_sets(code, name, is_active)
      values ($1, $2, true)
      on conflict (code) do update set
        name = excluded.name,
        is_active = true,
        updated_at = now()
      returning id
      `,
      [code, name],
    );
    res.json({ id: row.id });
  }),
);

app.patch(
  '/unit-sets/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    if (!name && isActive == null) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(`update unit_sets set ${sets.join(', ')} where id = $1::uuid`, params);
    res.json({ ok: true });
  }),
);

app.get(
  '/workstations',
  authRequired,
  asyncRoute(async (req, res) => {
    const rows = await queryAll(
      `
      select id, code, name, is_active as "isActive"
      from workstations
      order by name asc
      `,
      [],
    );
    res.json(rows);
  }),
);

app.post(
  '/workstations',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const code = (req.body?.code ?? '').toString().trim();
    const name = (req.body?.name ?? '').toString().trim();
    if (!code) return res.status(400).json({ error: 'CODE_REQUIRED' });
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });

    const row = await queryOne(
      `
      insert into workstations(code, name, is_active)
      values ($1, $2, true)
      on conflict (code) do update set
        name = excluded.name,
        is_active = true,
        updated_at = now()
      returning id
      `,
      [code, name],
    );
    res.json({ id: row.id });
  }),
);

app.patch(
  '/workstations/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    if (!name && isActive == null) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(`update workstations set ${sets.join(', ')} where id = $1::uuid`, params);
    res.json({ ok: true });
  }),
);

app.get(
  '/account-periods',
  authRequired,
  asyncRoute(async (req, res) => {
    const rows = await queryAll(
      `
      select
        id,
        name,
        start_date as "startDate",
        end_date as "endDate",
        is_active as "isActive"
      from account_periods
      order by start_date desc, name desc
      `,
      [],
    );
    res.json(rows);
  }),
);

app.post(
  '/account-periods',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const name = (req.body?.name ?? '').toString().trim();
    const startDate = asDateString((req.body?.startDate ?? '').toString());
    const endDate = asDateString((req.body?.endDate ?? '').toString());

    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });
    if (!startDate) return res.status(400).json({ error: 'START_REQUIRED' });
    if (!endDate) return res.status(400).json({ error: 'END_REQUIRED' });

    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(`update account_periods set is_active=false, updated_at=now()`);
      const row = await client.query(
        `
        insert into account_periods(name, start_date, end_date, is_active)
        values ($1, $2::date, $3::date, true)
        returning id
        `,
        [name, startDate, endDate],
      );
      await client.query('commit');
      res.json({ id: row.rows[0]?.id });
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }),
);

app.patch(
  '/account-periods/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const startDateRaw = (req.body?.startDate ?? '').toString();
    const endDateRaw = (req.body?.endDate ?? '').toString();
    const startDate = startDateRaw ? asDateString(startDateRaw) : null;
    const endDate = endDateRaw ? asDateString(endDateRaw) : null;
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    if (!name && !startDate && !endDate && isActive == null) {
      return res.status(400).json({ error: 'NO_CHANGES' });
    }
    if (startDateRaw && !startDate) return res.status(400).json({ error: 'START_INVALID' });
    if (endDateRaw && !endDate) return res.status(400).json({ error: 'END_INVALID' });

    const client = await pool.connect();
    try {
      await client.query('begin');
      if (isActive === true) {
        await client.query(`update account_periods set is_active=false, updated_at=now() where id <> $1::uuid`, [id]);
      }

      const sets = [];
      const params = [id];
      const add = (sql, value) => {
        params.push(value);
        sets.push(sql.replace('?', `$${params.length}`));
      };
      if (name) add('name = ?', name);
      if (startDate) add('start_date = ?::date', startDate);
      if (endDate) add('end_date = ?::date', endDate);
      if (isActive != null) add('is_active = ?', isActive);
      sets.push('updated_at = now()');

      await client.query(`update account_periods set ${sets.join(', ')} where id = $1::uuid`, params);
      await client.query('commit');
      res.json({ ok: true });
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }),
);

app.get(
  '/crm/waste-warehouse',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const row = await queryOne(
      `
      select branch_id as "branchId", warehouse_id as "warehouseId"
      from branch_waste_warehouse
      where branch_id = $1::uuid
      limit 1
      `,
      [branchId],
    );

    res.json({ branchId, warehouseId: row?.warehouseId ?? null });
  }),
);

app.put(
  '/crm/waste-warehouse',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = (req.body?.branchId ?? '').toString().trim();
    const warehouseId = (req.body?.warehouseId ?? '').toString().trim();
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!warehouseId) return res.status(400).json({ error: 'WAREHOUSE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const wh = await queryOne(
      `select id, branch_id as "branchId" from inv_warehouses where id=$1::uuid`,
      [warehouseId],
    );
    if (!wh) return res.status(404).json({ error: 'NOT_FOUND' });
    if (wh.branchId !== branchId) return res.status(400).json({ error: 'BRANCH_MISMATCH' });

    await pool.query(
      `
      insert into branch_waste_warehouse(branch_id, warehouse_id)
      values ($1::uuid, $2::uuid)
      on conflict (branch_id) do update set
        warehouse_id = excluded.warehouse_id,
        updated_at = now()
      `,
      [branchId, warehouseId],
    );

    res.json({ ok: true });
  }),
);

app.get(
  '/min-max',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchIdRaw = (req.query?.branchId ?? '').toString().trim();
    const branchId =
      req.user?.role === 'branchUser' ? req.user.branchId : branchIdRaw;

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const rows = await queryAll(
      `
      select
        id,
        branch_id as "branchId",
        product_name as "productName",
        min_qty as "minQty",
        max_qty as "maxQty"
      from min_max_definitions
      where branch_id = $1::uuid
      order by lower(product_name) asc
      limit 2000
      `,
      [branchId],
    );
    res.json(rows);
  }),
);

app.post(
  '/min-max',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = (req.body?.branchId ?? '').toString().trim();
    const productName = (req.body?.productName ?? '').toString().trim();
    const minQty = toQty(req.body?.minQty);
    const maxQty = toQty(req.body?.maxQty);

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!productName) return res.status(400).json({ error: 'PRODUCT_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });
    if (minQty == null || maxQty == null) {
      return res.status(400).json({ error: 'MIN_MAX_REQUIRED' });
    }

    const row = await queryOne(
      `
      insert into min_max_definitions(branch_id, product_name, min_qty, max_qty)
      values ($1::uuid, $2, $3, $4)
      returning id
      `,
      [branchId, productName, minQty, maxQty],
    );
    res.json({ id: row.id });
  }),
);

app.delete(
  '/min-max/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const item = await queryOne(
      `select id, branch_id as "branchId" from min_max_definitions where id=$1::uuid`,
      [id],
    );
    if (!item) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, item.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    await pool.query(`delete from min_max_definitions where id=$1::uuid`, [id]);
    res.json({ ok: true });
  }),
);

app.get(
  '/unproduced-products',
  authRequired,
  asyncRoute(async (req, res) => {
    const q = (req.query?.q ?? '').toString().trim().toLowerCase();

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };

    if (q) {
      params.push(q);
      const p1 = `$${params.length}`;
      filters.push(`lower(product_name) like '%' || ${p1} || '%'`);
    }

    const where = filters.length ? `where ${filters.join(' and ')}` : '';
    const rows = await queryAll(
      `
      select id, product_name as "productName", is_blocked as "isBlocked"
      from unproduced_products
      ${where}
      order by lower(product_name) asc
      limit 2000
      `,
      params,
    );
    res.json(rows);
  }),
);

app.post(
  '/unproduced-products',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const productName = (req.body?.productName ?? '').toString().trim();
    const isBlockedRaw = req.body?.isBlocked;
    const isBlocked = typeof isBlockedRaw === 'boolean' ? isBlockedRaw : true;

    if (!productName) return res.status(400).json({ error: 'PRODUCT_REQUIRED' });

    const row = await queryOne(
      `
      insert into unproduced_products(product_name, is_blocked)
      values ($1, $2)
      on conflict (product_name) do update set
        is_blocked = excluded.is_blocked,
        updated_at = now()
      returning id
      `,
      [productName, isBlocked],
    );

    res.json({ id: row.id });
  }),
);

app.patch(
  '/unproduced-products/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const isBlockedRaw = req.body?.isBlocked;
    const isBlocked = typeof isBlockedRaw === 'boolean' ? isBlockedRaw : null;
    if (isBlocked == null) return res.status(400).json({ error: 'NO_CHANGES' });

    await pool.query(
      `update unproduced_products set is_blocked=$2, updated_at=now() where id=$1::uuid`,
      [id, isBlocked],
    );
    res.json({ ok: true });
  }),
);

app.get(
  '/inv/products',
  authRequired,
  asyncRoute(async (req, res) => {
    const q = (req.query?.q ?? '').toString().trim().toLowerCase();
    const activeRaw = (req.query?.active ?? '').toString().trim();
    const onlyActive = activeRaw === '1' || activeRaw.toLowerCase() == 'true';

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };

    if (onlyActive) add('is_active = ?', true);
    if (q) {
      params.push(q);
      const p1 = `$${params.length}`;
      params.push(q);
      const p2 = `$${params.length}`;
      filters.push(
        `(lower(name) like '%' || ${p1} || '%' or lower(coalesce(code,'')) like '%' || ${p2} || '%')`,
      );
    }

    const where = filters.length ? `where ${filters.join(' and ')}` : '';
    const rows = await queryAll(
      `
      select id, code, name, unit, is_active as "isActive"
      from inv_products
      ${where}
      order by name asc
      limit 1000
      `,
      params,
    );
    res.json(rows);
  }),
);

app.post(
  '/inv/products',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const name = (req.body?.name ?? '').toString().trim();
    const unit = (req.body?.unit ?? 'adet').toString().trim() || 'adet';
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });
    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw || `${slugify(name)}-${Math.floor(Math.random() * 9000 + 1000)}`;

    const row = await queryOne(
      `
      insert into inv_products(code, name, unit, is_active)
      values ($1, $2, $3, true)
      on conflict (code) do update set
        name = excluded.name,
        unit = excluded.unit,
        is_active = true,
        updated_at = now()
      returning id
      `,
      [code, name, unit],
    );
    res.json({ id: row.id });
  }),
);

app.patch(
  '/inv/products/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const unit = (req.body?.unit ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    if (!name && !unit && isActive == null) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (unit) add('unit = ?', unit);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(
      `update inv_products set ${sets.join(', ')} where id = $1::uuid`,
      params,
    );
    res.json({ ok: true });
  }),
);

app.get(
  '/inv/warehouses',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim() || null;
    if (branchId && !canAccessBranch(req, branchId)) {
      return res.status(403).json({ error: 'FORBIDDEN' });
    }

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };
    if (branchId) add('branch_id = ?::uuid', branchId);
    const where = filters.length ? `where ${filters.join(' and ')}` : '';

    const rows = await queryAll(
      `
      select id, branch_id as "branchId", code, name, is_active as "isActive"
      from inv_warehouses
      ${where}
      order by name asc
      limit 1000
      `,
      params,
    );
    res.json(rows);
  }),
);

app.post(
  '/inv/warehouses',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = (req.body?.branchId ?? '').toString().trim();
    const name = (req.body?.name ?? '').toString().trim();
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!name) return res.status(400).json({ error: 'NAME_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw || `${slugify(name)}-${Math.floor(Math.random() * 9000 + 1000)}`;

    const row = await queryOne(
      `
      insert into inv_warehouses(branch_id, code, name, is_active)
      values ($1::uuid, $2, $3, true)
      on conflict (branch_id, code) do update set
        name = excluded.name,
        is_active = true,
        updated_at = now()
      returning id
      `,
      [branchId, code, name],
    );
    res.json({ id: row.id });
  }),
);

app.patch(
  '/inv/warehouses/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const name = (req.body?.name ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    const wh = await queryOne(
      `select id, branch_id as "branchId" from inv_warehouses where id=$1::uuid`,
      [id],
    );
    if (!wh) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, wh.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    if (!name && isActive == null) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (name) add('name = ?', name);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(
      `update inv_warehouses set ${sets.join(', ')} where id = $1::uuid`,
      params,
    );
    res.json({ ok: true });
  }),
);

app.get(
  '/inv/invoices',
  authRequired,
  asyncRoute(async (req, res) => {
    const from = asDateString(req.query?.from);
    const to = asDateString(req.query?.to);
    const branchIdRaw = (req.query?.branchId ?? '').toString().trim() || null;
    const branchId = req.user?.role === 'branchUser' ? req.user.branchId : branchIdRaw;

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const filters = ['i.branch_id = $1::uuid'];
    const params = [branchId];
    if (from) {
      params.push(from);
      filters.push(`i.invoice_date >= $${params.length}::date`);
    }
    if (to) {
      params.push(to);
      filters.push(`i.invoice_date <= $${params.length}::date`);
    }
    const where = `where ${filters.join(' and ')}`;

    const rows = await queryAll(
      `
      with totals as (
        select invoice_id, coalesce(sum(quantity * unit_price),0) as total
        from inv_invoice_lines
        group by invoice_id
      )
      select
        i.id,
        i.branch_id as "branchId",
        i.invoice_no as "invoiceNo",
        i.invoice_date as "invoiceDate",
        i.vendor_name as "vendorName",
        i.notes,
        i.payment_type_id as "paymentTypeId",
        i.income_center_id as "incomeCenterId",
        i.discount_rate as "discountRate",
        i.discount_amount as "discountAmount",
        i.meal_voucher_discount as "mealVoucherDiscount",
        i.payment_date as "paymentDate",
        coalesce(t.total,0)::numeric(14,2) as "total"
      from inv_invoices i
      left join totals t on t.invoice_id = i.id
      ${where}
      order by i.invoice_date desc, i.created_at desc
      limit 500
      `,
      params,
    );
    res.json(rows);
  }),
);

app.post(
  '/inv/invoices',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = (req.body?.branchId ?? '').toString().trim();
    const invoiceNo = (req.body?.invoiceNo ?? '').toString().trim();
    const invoiceDate = asDateString((req.body?.invoiceDate ?? '').toString());
    const vendorName = (req.body?.vendorName ?? '').toString().trim() || null;
    const notes = (req.body?.notes ?? '').toString().trim() || null;
    const paymentTypeId = (req.body?.paymentTypeId ?? '').toString().trim() || null;
    const incomeCenterId = (req.body?.incomeCenterId ?? '').toString().trim() || null;
    const discountRate = toMoney(req.body?.discountRate);
    const discountAmount = toMoney(req.body?.discountAmount);
    const mealVoucherDiscount = toMoney(req.body?.mealVoucherDiscount);
    const paymentDate = asDateString((req.body?.paymentDate ?? '').toString());

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!invoiceNo) return res.status(400).json({ error: 'NO_REQUIRED' });
    if (!invoiceDate) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const row = await queryOne(
      `
      insert into inv_invoices(
        branch_id,
        invoice_no,
        invoice_date,
        vendor_name,
        notes,
        payment_type_id,
        income_center_id,
        discount_rate,
        discount_amount,
        meal_voucher_discount,
        payment_date,
        created_by_user_id
      )
      values ($1::uuid, $2, $3::date, $4, $5, $6::uuid, $7::uuid, $8, $9, $10, $11::date, $12::uuid)
      on conflict (branch_id, invoice_no) do update set
        invoice_date = excluded.invoice_date,
        vendor_name = excluded.vendor_name,
        notes = excluded.notes,
        payment_type_id = excluded.payment_type_id,
        income_center_id = excluded.income_center_id,
        discount_rate = excluded.discount_rate,
        discount_amount = excluded.discount_amount,
        meal_voucher_discount = excluded.meal_voucher_discount,
        payment_date = excluded.payment_date,
        updated_at = now()
      returning id
      `,
      [
        branchId,
        invoiceNo,
        invoiceDate,
        vendorName,
        notes,
        paymentTypeId,
        incomeCenterId,
        discountRate,
        discountAmount,
        mealVoucherDiscount,
        paymentDate || null,
        req.user.sub,
      ],
    );
    res.json({ id: row.id });
  }),
);

app.get(
  '/inv/invoices/:id',
  authRequired,
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const header = await queryOne(
      `
      select
        id,
        branch_id as "branchId",
        invoice_no as "invoiceNo",
        invoice_date as "invoiceDate",
        vendor_name as "vendorName",
        notes,
        payment_type_id as "paymentTypeId",
        income_center_id as "incomeCenterId",
        discount_rate as "discountRate",
        discount_amount as "discountAmount",
        meal_voucher_discount as "mealVoucherDiscount",
        payment_date as "paymentDate"
      from inv_invoices
      where id = $1::uuid
      `,
      [id],
    );
    if (!header) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, header.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const lines = await queryAll(
      `
      select
        id,
        invoice_id as "invoiceId",
        product_id as "productId",
        description,
        coalesce(unit, '') as unit,
        quantity,
        unit_price as "unitPrice",
        (quantity * unit_price)::numeric(14,4) as "lineTotal",
        p.code as "productCode",
        p.name as "productName"
      from inv_invoice_lines
      left join inv_products p on p.id = product_id
      where invoice_id = $1::uuid
      order by created_at asc
      `,
      [id],
    );

    res.json({ header, lines });
  }),
);

app.patch(
  '/inv/invoices/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const existing = await queryOne(
      `select id, branch_id as "branchId" from inv_invoices where id=$1::uuid`,
      [id],
    );
    if (!existing) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, existing.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const invoiceNo = (req.body?.invoiceNo ?? '').toString().trim();
    const vendorName = (req.body?.vendorName ?? '').toString().trim();
    const notes = (req.body?.notes ?? '').toString().trim();
    const paymentTypeIdRaw = (req.body?.paymentTypeId ?? '').toString().trim();
    const incomeCenterIdRaw = (req.body?.incomeCenterId ?? '').toString().trim();
    const paymentTypeId = paymentTypeIdRaw.length === 0 ? null : paymentTypeIdRaw;
    const incomeCenterId = incomeCenterIdRaw.length === 0 ? null : incomeCenterIdRaw;
    const discountRate = req.body?.discountRate != null ? toMoney(req.body?.discountRate) : null;
    const discountAmount = req.body?.discountAmount != null ? toMoney(req.body?.discountAmount) : null;
    const mealVoucherDiscount = req.body?.mealVoucherDiscount != null ? toMoney(req.body?.mealVoucherDiscount) : null;
    const paymentDateRaw = (req.body?.paymentDate ?? '').toString();
    const paymentDate = paymentDateRaw ? asDateString(paymentDateRaw) : null;
    const invoiceDateRaw = (req.body?.invoiceDate ?? '').toString();
    const invoiceDate = invoiceDateRaw ? asDateString(invoiceDateRaw) : null;
    if (invoiceDateRaw && !invoiceDate) return res.status(400).json({ error: 'DATE_INVALID' });
    if (paymentDateRaw && !paymentDate) return res.status(400).json({ error: 'PAYMENT_DATE_INVALID' });
    if (req.body?.discountRate != null && discountRate == null) return res.status(400).json({ error: 'DISCOUNT_RATE_INVALID' });
    if (req.body?.discountAmount != null && discountAmount == null) return res.status(400).json({ error: 'DISCOUNT_AMOUNT_INVALID' });
    if (req.body?.mealVoucherDiscount != null && mealVoucherDiscount == null) return res.status(400).json({ error: 'MEAL_VOUCHER_DISCOUNT_INVALID' });

    if (
      !invoiceNo &&
      !vendorName &&
      !notes &&
      !invoiceDate &&
      paymentTypeIdRaw.length === 0 &&
      incomeCenterIdRaw.length === 0 &&
      req.body?.discountRate == null &&
      req.body?.discountAmount == null &&
      req.body?.mealVoucherDiscount == null &&
      !paymentDateRaw
    ) {
      return res.status(400).json({ error: 'NO_CHANGES' });
    }

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (invoiceNo) add('invoice_no = ?', invoiceNo);
    if (invoiceDate) add('invoice_date = ?::date', invoiceDate);
    if (vendorName) add('vendor_name = ?', vendorName);
    if (notes) add('notes = ?', notes);
    if (paymentTypeIdRaw.length > 0) add('payment_type_id = ?::uuid', paymentTypeId);
    if (incomeCenterIdRaw.length > 0) add('income_center_id = ?::uuid', incomeCenterId);
    if (req.body?.discountRate != null) add('discount_rate = ?', discountRate);
    if (req.body?.discountAmount != null) add('discount_amount = ?', discountAmount);
    if (req.body?.mealVoucherDiscount != null) add('meal_voucher_discount = ?', mealVoucherDiscount);
    if (paymentDate) add('payment_date = ?::date', paymentDate);
    sets.push('updated_at = now()');

    await pool.query(`update inv_invoices set ${sets.join(', ')} where id = $1::uuid`, params);
    res.json({ ok: true });
  }),
);

app.post(
  '/inv/invoices/:id/lines',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const invoiceId = req.params.id;
    const header = await queryOne(
      `select id, branch_id as "branchId" from inv_invoices where id=$1::uuid`,
      [invoiceId],
    );
    if (!header) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, header.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const productId = (req.body?.productId ?? '').toString().trim() || null;
    const descriptionRaw = (req.body?.description ?? '').toString().trim();
    const quantity = toQty(req.body?.quantity);
    const unitPrice = toMoney(req.body?.unitPrice);

    let description = descriptionRaw;
    let unit = (req.body?.unit ?? '').toString().trim() || null;

    if (productId) {
      const p = await queryOne(
        `select id, name, unit from inv_products where id=$1::uuid limit 1`,
        [productId],
      );
      if (!p) return res.status(404).json({ error: 'PRODUCT_NOT_FOUND' });
      if (!description) description = p.name;
      if (!unit) unit = p.unit;
    }

    if (!description) return res.status(400).json({ error: 'DESC_REQUIRED' });
    if (quantity == null) return res.status(400).json({ error: 'QTY_REQUIRED' });
    if (unitPrice == null) return res.status(400).json({ error: 'PRICE_REQUIRED' });

    const row = await queryOne(
      `
      insert into inv_invoice_lines(invoice_id, product_id, description, unit, quantity, unit_price)
      values ($1::uuid, $2::uuid, $3, $4, $5, $6)
      returning id
      `,
      [invoiceId, productId, description, unit, quantity, unitPrice],
    );
    res.json({ id: row.id });
  }),
);

app.patch(
  '/inv/invoice-lines/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const line = await queryOne(
      `
      select l.id, i.branch_id as "branchId"
      from inv_invoice_lines l
      join inv_invoices i on i.id = l.invoice_id
      where l.id = $1::uuid
      `,
      [id],
    );
    if (!line) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, line.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const productId = (req.body?.productId ?? '').toString().trim() || null;
    const descriptionRaw = (req.body?.description ?? '').toString().trim();
    const unitRaw = (req.body?.unit ?? '').toString().trim();
    const quantity = req.body?.quantity != null ? toQty(req.body?.quantity) : null;
    const unitPrice = req.body?.unitPrice != null ? toMoney(req.body?.unitPrice) : null;

    if (!productId && !descriptionRaw && !unitRaw && quantity == null && unitPrice == null) {
      return res.status(400).json({ error: 'NO_CHANGES' });
    }
    if (req.body?.quantity != null && quantity == null) return res.status(400).json({ error: 'QTY_INVALID' });
    if (req.body?.unitPrice != null && unitPrice == null) return res.status(400).json({ error: 'PRICE_INVALID' });

    let description = descriptionRaw;
    let unit = unitRaw || null;

    if (productId) {
      const p = await queryOne(
        `select id, name, unit from inv_products where id=$1::uuid limit 1`,
        [productId],
      );
      if (!p) return res.status(404).json({ error: 'PRODUCT_NOT_FOUND' });
      if (!description) description = p.name;
      if (!unit) unit = p.unit;
    }

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (productId) add('product_id = ?::uuid', productId);
    if (description) add('description = ?', description);
    if (unitRaw.length > 0 || productId) add('unit = ?', unit);
    if (quantity != null) add('quantity = ?', quantity);
    if (unitPrice != null) add('unit_price = ?', unitPrice);
    sets.push('updated_at = now()');

    await pool.query(`update inv_invoice_lines set ${sets.join(', ')} where id = $1::uuid`, params);
    res.json({ ok: true });
  }),
);

app.delete(
  '/inv/invoice-lines/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const line = await queryOne(
      `
      select l.id, i.branch_id as "branchId"
      from inv_invoice_lines l
      join inv_invoices i on i.id = l.invoice_id
      where l.id = $1::uuid
      `,
      [id],
    );
    if (!line) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, line.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    await pool.query(`delete from inv_invoice_lines where id = $1::uuid`, [id]);
    res.json({ ok: true });
  }),
);

app.get(
  '/inv/open-delivery-notes',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchIdRaw = (req.query?.branchId ?? '').toString().trim() || null;
    const branchId = req.user?.role === 'branchUser' ? req.user.branchId : branchIdRaw;
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });
    res.json([]);
  }),
);

app.get(
  '/inv/open-purchase-orders',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchIdRaw = (req.query?.branchId ?? '').toString().trim() || null;
    const branchId = req.user?.role === 'branchUser' ? req.user.branchId : branchIdRaw;
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });
    res.json([]);
  }),
);

app.get(
  '/inv/stock-transactions',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim() || null;
    const warehouseId = (req.query?.warehouseId ?? '').toString().trim() || null;
    const from = asDateString(req.query?.from);
    const to = asDateString(req.query?.to);

    if (branchId && !canAccessBranch(req, branchId)) {
      return res.status(403).json({ error: 'FORBIDDEN' });
    }

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };
    if (branchId) add('t.branch_id = ?::uuid', branchId);
    if (warehouseId) add('t.warehouse_id = ?::uuid', warehouseId);
    if (from) add('t.business_date >= ?::date', from);
    if (to) add('t.business_date <= ?::date', to);

    const where = filters.length ? `where ${filters.join(' and ')}` : '';
    const rows = await queryAll(
      `
      select
        t.id,
        t.branch_id as "branchId",
        t.warehouse_id as "warehouseId",
        t.business_date as "businessDate",
        t.kind,
        t.reference_no as "referenceNo",
        t.notes,
        t.created_by_user_id as "createdByUserId",
        (
          select count(*)::int
          from inv_stock_transaction_lines l
          where l.transaction_id = t.id
        ) as "linesCount"
      from inv_stock_transactions t
      ${where}
      order by t.business_date desc, t.created_at desc
      limit 500
      `,
      params,
    );
    res.json(rows);
  }),
);

app.get(
  '/inv/stock-transactions/:id',
  authRequired,
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const tx = await queryOne(
      `
      select
        id,
        branch_id as "branchId",
        warehouse_id as "warehouseId",
        business_date as "businessDate",
        kind,
        reference_no as "referenceNo",
        notes,
        created_by_user_id as "createdByUserId"
      from inv_stock_transactions
      where id = $1::uuid
      `,
      [id],
    );
    if (!tx) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, tx.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const lines = await queryAll(
      `
      select product_id as "productId", quantity, unit_cost as "unitCost"
      from inv_stock_transaction_lines
      where transaction_id = $1::uuid
      order by created_at asc
      `,
      [id],
    );

    res.json({ ...tx, lines });
  }),
);

app.post(
  '/inv/stock-transactions',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = (req.body?.branchId ?? '').toString().trim();
    const warehouseId = (req.body?.warehouseId ?? '').toString().trim();
    const businessDate = asDateString(req.body?.businessDate);
    const kind = (req.body?.kind ?? '').toString().trim();
    const referenceNo = (req.body?.referenceNo ?? '').toString().trim() || null;
    const notes = (req.body?.notes ?? '').toString().trim() || null;
    const lines = Array.isArray(req.body?.lines) ? req.body.lines : null;

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!warehouseId) return res.status(400).json({ error: 'WAREHOUSE_REQUIRED' });
    if (!businessDate) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!kind) return res.status(400).json({ error: 'KIND_REQUIRED' });
    if (!lines || lines.length === 0) return res.status(400).json({ error: 'LINES_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const wh = await queryOne(
      `select id, branch_id as "branchId" from inv_warehouses where id=$1::uuid`,
      [warehouseId],
    );
    if (!wh) return res.status(400).json({ error: 'WAREHOUSE_NOT_FOUND' });
    if (wh.branchId !== branchId) return res.status(400).json({ error: 'WAREHOUSE_BRANCH_MISMATCH' });

    const client = await pool.connect();
    try {
      await client.query('begin');
      const header = await client.query(
        `
        insert into inv_stock_transactions(
          branch_id, warehouse_id, business_date, kind, reference_no, notes, created_by_user_id
        )
        values ($1::uuid, $2::uuid, $3::date, $4, $5, $6, $7::uuid)
        returning id
        `,
        [branchId, warehouseId, businessDate, kind, referenceNo, notes, req.user.sub],
      );
      const id = header.rows[0].id;

      for (const line of lines) {
        const productId = (line?.productId ?? '').toString().trim();
        const quantity = toQty(line?.quantity);
        const unitCost = toMoney(line?.unitCost) ?? 0;
        if (!productId || quantity == null) continue;
        await client.query(
          `
          insert into inv_stock_transaction_lines(transaction_id, product_id, quantity, unit_cost)
          values ($1::uuid, $2::uuid, $3::numeric, $4::numeric)
          `,
          [id, productId, quantity, unitCost],
        );
      }

      await client.query('commit');
      res.json({ id });
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }),
);

app.get(
  '/inv/stock-on-hand',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    const warehouseId = (req.query?.warehouseId ?? '').toString().trim() || null;
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };
    add('t.branch_id = ?::uuid', branchId);
    if (warehouseId) add('t.warehouse_id = ?::uuid', warehouseId);
    const where = filters.length ? `where ${filters.join(' and ')}` : '';

    const rows = await queryAll(
      `
      select
        p.id as "productId",
        p.name as "productName",
        p.unit,
        coalesce(sum(l.quantity),0)::numeric(14,3) as quantity
      from inv_stock_transaction_lines l
      join inv_stock_transactions t on t.id = l.transaction_id
      join inv_products p on p.id = l.product_id
      ${where}
      group by p.id, p.name, p.unit
      order by p.name asc
      limit 2000
      `,
      params,
    );
    res.json(rows);
  }),
);

async function loadOnHandByProductId({
  client,
  branchId,
  warehouseId,
  asOfDate,
}) {
  const rows = await client.query(
    `
    select
      l.product_id as "productId",
      coalesce(sum(l.quantity),0)::numeric(14,3) as quantity
    from inv_stock_transaction_lines l
    join inv_stock_transactions t on t.id = l.transaction_id
    where
      t.branch_id = $1::uuid
      and t.warehouse_id = $2::uuid
      and t.business_date <= $3::date
    group by l.product_id
    `,
    [branchId, warehouseId, asOfDate],
  );
  const m = new Map();
  for (const r of rows.rows) m.set(r.productId, Number(r.quantity));
  return m;
}

app.get(
  '/inv/stock-counts',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim() || null;
    const warehouseId = (req.query?.warehouseId ?? '').toString().trim() || null;
    const from = asDateString(req.query?.from);
    const to = asDateString(req.query?.to);
    const status = (req.query?.status ?? '').toString().trim() || null;

    if (branchId && !canAccessBranch(req, branchId)) {
      return res.status(403).json({ error: 'FORBIDDEN' });
    }

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };

    if (branchId) add('c.branch_id = ?::uuid', branchId);
    if (warehouseId) add('c.warehouse_id = ?::uuid', warehouseId);
    if (from) add('c.business_date >= ?::date', from);
    if (to) add('c.business_date <= ?::date', to);
    if (status) add('c.status = ?', status);

    if (req.user?.role === 'branchUser') {
      add('c.branch_id = ?::uuid', req.user.branchId);
    }

    const where = filters.length ? `where ${filters.join(' and ')}` : '';
    const rows = await queryAll(
      `
      select
        c.id,
        c.branch_id as "branchId",
        b.name as "branchName",
        c.warehouse_id as "warehouseId",
        w.name as "warehouseName",
        c.business_date as "businessDate",
        c.status,
        c.created_by_user_id as "createdByUserId",
        c.approved_by_user_id as "approvedByUserId",
        c.rejection_reason as "rejectionReason",
        (
          select count(*)::int
          from inv_stock_count_lines l
          where l.count_id = c.id
        ) as "linesCount",
        (
          select coalesce(sum(abs(l.diff_qty)),0)::numeric(14,3)
          from inv_stock_count_lines l
          where l.count_id = c.id
        ) as "diffAbsTotal"
      from inv_stock_counts c
      join branches b on b.id = c.branch_id
      join inv_warehouses w on w.id = c.warehouse_id
      ${where}
      order by c.business_date desc, c.created_at desc
      limit 500
      `,
      params,
    );
    res.json(rows);
  }),
);

app.post(
  '/inv/stock-counts',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.body?.branchId ?? '').toString().trim();
    const warehouseId = (req.body?.warehouseId ?? '').toString().trim();
    const businessDate = asDateString(req.body?.businessDate);

    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!warehouseId) return res.status(400).json({ error: 'WAREHOUSE_REQUIRED' });
    if (!businessDate) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const wh = await queryOne(
      `select id, branch_id as "branchId" from inv_warehouses where id=$1::uuid`,
      [warehouseId],
    );
    if (!wh) return res.status(400).json({ error: 'WAREHOUSE_NOT_FOUND' });
    if (wh.branchId !== branchId) return res.status(400).json({ error: 'WAREHOUSE_BRANCH_MISMATCH' });

    const row = await queryOne(
      `
      insert into inv_stock_counts(branch_id, warehouse_id, business_date, status, created_by_user_id)
      values ($1::uuid, $2::uuid, $3::date, 'draft', $4::uuid)
      on conflict (warehouse_id, business_date)
      do update set updated_at = now()
      returning id
      `,
      [branchId, warehouseId, businessDate, req.user.sub],
    );
    res.json({ id: row.id });
  }),
);

app.get(
  '/inv/stock-counts/:id',
  authRequired,
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const header = await queryOne(
      `
      select
        c.id,
        c.branch_id as "branchId",
        b.name as "branchName",
        c.warehouse_id as "warehouseId",
        w.name as "warehouseName",
        c.business_date as "businessDate",
        c.status,
        c.created_by_user_id as "createdByUserId",
        c.approved_by_user_id as "approvedByUserId",
        c.rejection_reason as "rejectionReason"
      from inv_stock_counts c
      join branches b on b.id = c.branch_id
      join inv_warehouses w on w.id = c.warehouse_id
      where c.id = $1::uuid
      `,
      [id],
    );
    if (!header) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, header.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const lines = await queryAll(
      `
      select
        l.product_id as "productId",
        p.name as "productName",
        p.unit,
        l.counted_qty as "countedQty",
        l.onhand_qty as "onhandQty",
        l.diff_qty as "diffQty"
      from inv_stock_count_lines l
      join inv_products p on p.id = l.product_id
      where l.count_id = $1::uuid
      order by p.name asc
      `,
      [id],
    );

    const totals = await queryOne(
      `
      select
        coalesce(sum(counted_qty),0)::numeric(14,3) as "countedTotal",
        coalesce(sum(onhand_qty),0)::numeric(14,3) as "onhandTotal",
        coalesce(sum(diff_qty),0)::numeric(14,3) as "diffTotal",
        coalesce(sum(abs(diff_qty)),0)::numeric(14,3) as "diffAbsTotal"
      from inv_stock_count_lines
      where count_id = $1::uuid
      `,
      [id],
    );

    res.json({ ...header, lines, totals });
  }),
);

app.patch(
  '/inv/stock-counts/:id/lines',
  authRequired,
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const incoming = Array.isArray(req.body?.lines) ? req.body.lines : null;
    if (!incoming) return res.status(400).json({ error: 'LINES_REQUIRED' });

    const count = await queryOne(
      `
      select
        id,
        branch_id as "branchId",
        warehouse_id as "warehouseId",
        business_date as "businessDate",
        status,
        created_by_user_id as "createdByUserId"
      from inv_stock_counts
      where id = $1::uuid
      `,
      [id],
    );
    if (!count) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, count.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const isManager = req.user.role === 'manager' || req.user.role === 'accounting';
    const isOwner = req.user.sub === count.createdByUserId;
    const canEdit =
      isManager || (isOwner && (count.status === 'draft' || count.status === 'rejected'));
    if (!canEdit) return res.status(403).json({ error: 'FORBIDDEN' });

    const normalized = [];
    for (const l of incoming) {
      const productId = (l?.productId ?? '').toString().trim();
      const countedQty = toQty(l?.countedQty ?? l?.quantity);
      if (!productId || countedQty == null) continue;
      normalized.push({ productId, countedQty });
    }

    const client = await pool.connect();
    try {
      await client.query('begin');

      const onhandByProductId = await loadOnHandByProductId({
        client,
        branchId: count.branchId,
        warehouseId: count.warehouseId,
        asOfDate: count.businessDate,
      });

      await client.query(`delete from inv_stock_count_lines where count_id = $1::uuid`, [id]);

      for (const l of normalized) {
        const onhandQty = onhandByProductId.get(l.productId) ?? 0;
        const diffQty = Number(l.countedQty) - Number(onhandQty);
        await client.query(
          `
          insert into inv_stock_count_lines(count_id, product_id, counted_qty, onhand_qty, diff_qty)
          values ($1::uuid, $2::uuid, $3::numeric, $4::numeric, $5::numeric)
          `,
          [id, l.productId, l.countedQty, onhandQty, diffQty],
        );
      }

      await client.query(`update inv_stock_counts set updated_at=now() where id=$1::uuid`, [id]);

      await client.query('commit');
      res.json({ ok: true });
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }),
);

app.post(
  '/inv/stock-counts/:id/submit',
  authRequired,
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const count = await queryOne(
      `
      select
        id,
        branch_id as "branchId",
        status,
        created_by_user_id as "createdByUserId"
      from inv_stock_counts
      where id = $1::uuid
      `,
      [id],
    );
    if (!count) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, count.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const isOwner = req.user.sub === count.createdByUserId;
    if (!isOwner) return res.status(403).json({ error: 'FORBIDDEN' });
    if (!(count.status === 'draft' || count.status === 'rejected')) {
      return res.status(400).json({ error: 'INVALID_STATUS' });
    }

    const hasLines = await queryOne(
      `select exists(select 1 from inv_stock_count_lines where count_id = $1::uuid) as ok`,
      [id],
    );
    if (!hasLines?.ok) return res.status(400).json({ error: 'LINES_REQUIRED' });

    await pool.query(
      `update inv_stock_counts set status='submitted', updated_at=now() where id=$1::uuid`,
      [id],
    );
    res.json({ ok: true });
  }),
);

app.post(
  '/inv/stock-counts/:id/approve',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const count = await queryOne(
      `
      select
        id,
        branch_id as "branchId",
        warehouse_id as "warehouseId",
        business_date as "businessDate",
        status
      from inv_stock_counts
      where id = $1::uuid
      `,
      [id],
    );
    if (!count) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, count.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });
    if (count.status !== 'submitted') return res.status(400).json({ error: 'INVALID_STATUS' });

    const lines = await queryAll(
      `
      select product_id as "productId", diff_qty as "diffQty"
      from inv_stock_count_lines
      where count_id = $1::uuid
      `,
      [id],
    );

    const adjustments = lines
      .map((l) => ({ productId: l.productId, quantity: toQty(l.diffQty) }))
      .filter((l) => l.productId && l.quantity != null && Math.abs(Number(l.quantity)) > 0.0005);

    const client = await pool.connect();
    try {
      await client.query('begin');

      if (adjustments.length > 0) {
        const txHeader = await client.query(
          `
          insert into inv_stock_transactions(
            branch_id, warehouse_id, business_date, kind, reference_no, notes, created_by_user_id
          )
          values ($1::uuid, $2::uuid, $3::date, $4, $5, $6, $7::uuid)
          returning id
          `,
          [
            count.branchId,
            count.warehouseId,
            count.businessDate,
            'adjustment',
            `COUNT:${id}`,
            `Stock count adjustment for ${id}`,
            req.user.sub,
          ],
        );
        const txId = txHeader.rows[0].id;

        for (const a of adjustments) {
          await client.query(
            `
            insert into inv_stock_transaction_lines(transaction_id, product_id, quantity, unit_cost)
            values ($1::uuid, $2::uuid, $3::numeric, 0::numeric)
            `,
            [txId, a.productId, a.quantity],
          );
        }
      }

      await client.query(
        `update inv_stock_counts set status='approved', approved_by_user_id=$2::uuid, rejection_reason=null, updated_at=now() where id=$1::uuid`,
        [id, req.user.sub],
      );

      await client.query('commit');
      res.json({ ok: true });
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }),
);

app.post(
  '/inv/stock-counts/:id/reject',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const reason = (req.body?.reason ?? '').toString().trim();
    if (!reason) return res.status(400).json({ error: 'REASON_REQUIRED' });

    const count = await queryOne(
      `
      select id, branch_id as "branchId", status
      from inv_stock_counts
      where id = $1::uuid
      `,
      [id],
    );
    if (!count) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, count.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });
    if (count.status !== 'submitted') return res.status(400).json({ error: 'INVALID_STATUS' });

    await pool.query(
      `update inv_stock_counts set status='rejected', approved_by_user_id=null, rejection_reason=$2, updated_at=now() where id=$1::uuid`,
      [id, reason],
    );
    res.json({ ok: true });
  }),
);

app.get(
  '/inv/recipes',
  authRequired,
  asyncRoute(async (req, res) => {
    const q = (req.query?.q ?? '').toString().trim().toLowerCase();
    const activeRaw = (req.query?.active ?? '').toString().trim();
    const onlyActive = activeRaw === '1' || activeRaw.toLowerCase() == 'true';

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };

    if (onlyActive) add('r.is_active = ?', true);
    if (q) {
      params.push(q);
      const p1 = `$${params.length}`;
      params.push(q);
      const p2 = `$${params.length}`;
      filters.push(
        `(lower(coalesce(r.name,'')) like '%' || ${p1} || '%' or lower(coalesce(r.code,'')) like '%' || ${p2} || '%')`,
      );
    }

    const where = filters.length ? `where ${filters.join(' and ')}` : '';
    const rows = await queryAll(
      `
      select
        r.id,
        r.product_id as "productId",
        p.name as "productName",
        r.code,
        r.name,
        r.description,
        r.yield_qty as "yieldQty",
        r.yield_unit as "yieldUnit",
        r.gim_oran as "gimOran",
        r.is_active as "isActive",
        (
          select count(*)::int
          from inv_recipe_lines l
          where l.recipe_id = r.id
        ) as "linesCount"
      from inv_recipes r
      join inv_products p on p.id = r.product_id
      ${where}
      order by r.updated_at desc, r.created_at desc
      limit 1000
      `,
      params,
    );
    res.json(rows);
  }),
);

app.get(
  '/inv/recipes/:id',
  authRequired,
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const header = await queryOne(
      `
      select
        r.id,
        r.product_id as "productId",
        p.name as "productName",
        r.code,
        r.name,
        r.description,
        r.yield_qty as "yieldQty",
        r.yield_unit as "yieldUnit",
        r.gim_oran as "gimOran",
        r.is_active as "isActive"
      from inv_recipes r
      join inv_products p on p.id = r.product_id
      where r.id = $1::uuid
      `,
      [id],
    );
    if (!header) return res.status(404).json({ error: 'NOT_FOUND' });

    const lines = await queryAll(
      `
      with avg_cost as (
        select
          l.product_id,
          coalesce(avg(nullif(l.unit_cost,0)),0)::numeric(14,4) as avg_unit_cost
        from inv_stock_transaction_lines l
        group by l.product_id
      )
      select
        rl.ingredient_product_id as "ingredientProductId",
        ip.name as "ingredientProductName",
        coalesce(rl.unit, ip.unit, 'adet') as unit,
        rl.quantity,
        coalesce(rl.waste_rate,0)::numeric(18,5) as "wasteRate",
        coalesce(ac.avg_unit_cost,0)::numeric(14,4) as "avgUnitCost",
        (
          (rl.quantity * (1 + coalesce(rl.waste_rate,0))) * coalesce(ac.avg_unit_cost,0)
        )::numeric(14,4) as "lineCost"
      from inv_recipe_lines rl
      join inv_products ip on ip.id = rl.ingredient_product_id
      left join avg_cost ac on ac.product_id = rl.ingredient_product_id
      where rl.recipe_id = $1::uuid
      order by ip.name asc
      `,
      [id],
    );

    const totals = await queryOne(
      `
      with avg_cost as (
        select
          l.product_id,
          coalesce(avg(nullif(l.unit_cost,0)),0)::numeric(14,4) as avg_unit_cost
        from inv_stock_transaction_lines l
        group by l.product_id
      )
      select
        coalesce(
          sum((rl.quantity * (1 + coalesce(rl.waste_rate,0))) * coalesce(ac.avg_unit_cost,0)),
          0
        )::numeric(14,4) as "recipeCost"
      from inv_recipe_lines rl
      left join avg_cost ac on ac.product_id = rl.ingredient_product_id
      where rl.recipe_id = $1::uuid
      `,
      [id],
    );

    res.json({ ...header, lines, totals: totals ?? { recipeCost: 0 } });
  }),
);

app.post(
  '/inv/recipes',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const productId = (req.body?.productId ?? '').toString().trim();
    if (!productId) return res.status(400).json({ error: 'PRODUCT_REQUIRED' });

    const codeRaw = (req.body?.code ?? '').toString().trim();
    const code = codeRaw || null;
    const nameRaw = (req.body?.name ?? '').toString().trim();
    const description = (req.body?.description ?? '').toString().trim() || null;
    const yieldQty = toQty(req.body?.yieldQty) ?? 1;
    const yieldUnit = (req.body?.yieldUnit ?? 'adet').toString().trim() || 'adet';
    const gimOran = toMoney(req.body?.gimOran);
    const lines = Array.isArray(req.body?.lines) ? req.body.lines : [];

    const product = await queryOne(
      `select id, name, unit from inv_products where id=$1::uuid`,
      [productId],
    );
    if (!product) return res.status(400).json({ error: 'PRODUCT_NOT_FOUND' });
    const name = nameRaw || product.name;

    const client = await pool.connect();
    try {
      await client.query('begin');

      const header = await client.query(
        `
        insert into inv_recipes(product_id, code, name, description, yield_qty, yield_unit, gim_oran, is_active)
        values ($1::uuid, $2, $3, $4, $5::numeric, $6, $7::numeric, true)
        on conflict (product_id) do update set
          code = excluded.code,
          name = excluded.name,
          description = excluded.description,
          yield_qty = excluded.yield_qty,
          yield_unit = excluded.yield_unit,
          gim_oran = excluded.gim_oran,
          is_active = true,
          updated_at = now()
        returning id
        `,
        [productId, code, name, description, yieldQty, yieldUnit, gimOran],
      );
      const id = header.rows[0].id;

      await client.query(`delete from inv_recipe_lines where recipe_id=$1::uuid`, [id]);

      for (const l of lines) {
        const ingredientProductId = (l?.ingredientProductId ?? l?.productId ?? '').toString().trim();
        const quantity = toQty(l?.quantity);
        if (!ingredientProductId || quantity == null) continue;
        const unit = (l?.unit ?? '').toString().trim() || null;
        const wasteRate = toMoney(l?.wasteRate);
        await client.query(
          `
          insert into inv_recipe_lines(recipe_id, ingredient_product_id, quantity, unit, waste_rate)
          values ($1::uuid, $2::uuid, $3::numeric, $4, $5::numeric)
          `,
          [id, ingredientProductId, quantity, unit, wasteRate],
        );
      }

      await client.query('commit');
      res.json({ id });
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }),
);

app.patch(
  '/inv/recipes/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;
    const description = (req.body?.description ?? '').toString().trim();
    const name = (req.body?.name ?? '').toString().trim();
    const code = (req.body?.code ?? '').toString().trim();
    const yieldQty = toQty(req.body?.yieldQty);
    const yieldUnit = (req.body?.yieldUnit ?? '').toString().trim();
    const gimOran = toMoney(req.body?.gimOran);

    if (
      isActive == null &&
      !description &&
      !name &&
      !code &&
      yieldQty == null &&
      !yieldUnit &&
      gimOran == null
    ) {
      return res.status(400).json({ error: 'NO_CHANGES' });
    }

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (isActive != null) add('is_active = ?', isActive);
    if (description) add('description = ?', description);
    if (name) add('name = ?', name);
    if (code) add('code = ?', code);
    if (yieldQty != null) add('yield_qty = ?::numeric', yieldQty);
    if (yieldUnit) add('yield_unit = ?', yieldUnit);
    if (gimOran != null) add('gim_oran = ?::numeric', gimOran);
    sets.push('updated_at = now()');

    await pool.query(`update inv_recipes set ${sets.join(', ')} where id = $1::uuid`, params);
    res.json({ ok: true });
  }),
);

app.get(
  '/crm/firms',
  authRequired,
  asyncRoute(async (req, res) => {
    const q = (req.query?.q ?? '').toString().trim().toLowerCase();
    const activeRaw = (req.query?.active ?? '').toString().trim();
    const onlyActive = activeRaw === '1' || activeRaw.toLowerCase() == 'true';

    const filters = [];
    const params = [];
    const add = (sql, value) => {
      params.push(value);
      filters.push(sql.replace('?', `$${params.length}`));
    };

    if (onlyActive) add('f.is_active = ?', true);
    if (q) {
      params.push(q);
      const p1 = `$${params.length}`;
      params.push(q);
      const p2 = `$${params.length}`;
      params.push(q);
      const p3 = `$${params.length}`;
      filters.push(
        `(
          lower(coalesce(f.firm_name,'')) like '%' || ${p1} || '%'
          or lower(coalesce(f.trade_name,'')) like '%' || ${p2} || '%'
          or lower(coalesce(f.tax_no,'')) like '%' || ${p3} || '%'
        )`,
      );
    }

    const where = filters.length ? `where ${filters.join(' and ')}` : '';
    const rows = await queryAll(
      `
      select
        f.id,
        f.firm_name as "firmName",
        f.trade_name as "tradeName",
        f.integration_code as "integrationCode",
        f.firm_type as "firmType",
        f.is_current as "isCurrent",
        f.customer_group as "customerGroup",
        f.email,
        f.price_no as "priceNo",
        f.wholesale_price_no as "wholesalePriceNo",
        f.invoice_company as "invoiceCompany",
        f.general_discount as "generalDiscount",
        f.payment_method as "paymentMethod",
        f.tax_office as "taxOffice",
        f.tax_no as "taxNo",
        f.is_einvoice as "isEInvoice",
        f.cargo_code as "cargoCode",
        f.purchase_price_no as "purchasePriceNo",
        f.payment_vkn as "paymentVkn",
        f.iban,
        f.notes,
        f.is_active as "isActive",
        f.updated_at as "updatedAt"
      from crm_firms f
      ${where}
      order by f.updated_at desc
      limit 1000
      `,
      params,
    );
    res.json(rows);
  }),
);

app.get(
  '/crm/firms/:id',
  authRequired,
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const row = await queryOne(
      `
      select
        id,
        firm_name as "firmName",
        trade_name as "tradeName",
        integration_code as "integrationCode",
        firm_type as "firmType",
        is_current as "isCurrent",
        customer_group as "customerGroup",
        email,
        price_no as "priceNo",
        wholesale_price_no as "wholesalePriceNo",
        invoice_company as "invoiceCompany",
        general_discount as "generalDiscount",
        payment_method as "paymentMethod",
        tax_office as "taxOffice",
        tax_no as "taxNo",
        is_einvoice as "isEInvoice",
        cargo_code as "cargoCode",
        purchase_price_no as "purchasePriceNo",
        payment_vkn as "paymentVkn",
        iban,
        notes,
        is_active as "isActive",
        created_at as "createdAt",
        updated_at as "updatedAt"
      from crm_firms
      where id = $1::uuid
      `,
      [id],
    );
    if (!row) return res.status(404).json({ error: 'NOT_FOUND' });
    res.json(row);
  }),
);

app.post(
  '/crm/firms',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const firmName = (req.body?.firmName ?? '').toString().trim();
    if (!firmName) return res.status(400).json({ error: 'FIRM_NAME_REQUIRED' });

    const tradeName = (req.body?.tradeName ?? '').toString().trim() || null;
    const integrationCode = (req.body?.integrationCode ?? '').toString().trim() || null;
    const firmType = (req.body?.firmType ?? '').toString().trim() || null;
    const isCurrentRaw = req.body?.isCurrent;
    const isCurrent = typeof isCurrentRaw === 'boolean' ? isCurrentRaw : true;
    const customerGroup = (req.body?.customerGroup ?? '').toString().trim() || null;
    const email = (req.body?.email ?? '').toString().trim() || null;
    const priceNo = (req.body?.priceNo ?? '').toString().trim() || null;
    const wholesalePriceNo = (req.body?.wholesalePriceNo ?? '').toString().trim() || null;
    const invoiceCompany = (req.body?.invoiceCompany ?? '').toString().trim() || null;
    const generalDiscount = toMoney(req.body?.generalDiscount);
    const paymentMethod = (req.body?.paymentMethod ?? '').toString().trim() || null;
    const taxOffice = (req.body?.taxOffice ?? '').toString().trim() || null;
    const taxNo = (req.body?.taxNo ?? '').toString().trim() || null;
    const isEInvoiceRaw = req.body?.isEInvoice;
    const isEInvoice = typeof isEInvoiceRaw === 'boolean' ? isEInvoiceRaw : false;
    const cargoCode = (req.body?.cargoCode ?? '').toString().trim() || null;
    const purchasePriceNo = (req.body?.purchasePriceNo ?? '').toString().trim() || null;
    const paymentVkn = (req.body?.paymentVkn ?? '').toString().trim() || null;
    const iban = (req.body?.iban ?? '').toString().trim() || null;
    const notes = (req.body?.notes ?? '').toString().trim() || null;

    const row = await queryOne(
      `
      insert into crm_firms(
        firm_name,
        trade_name,
        integration_code,
        firm_type,
        is_current,
        customer_group,
        email,
        price_no,
        wholesale_price_no,
        invoice_company,
        general_discount,
        payment_method,
        tax_office,
        tax_no,
        is_einvoice,
        cargo_code,
        purchase_price_no,
        payment_vkn,
        iban,
        notes,
        is_active
      )
      values (
        $1,
        $2,
        $3,
        $4,
        $5::boolean,
        $6,
        $7,
        $8,
        $9,
        $10,
        $11::numeric,
        $12,
        $13,
        $14,
        $15::boolean,
        $16,
        $17,
        $18,
        $19,
        $20,
        true
      )
      returning id
      `,
      [
        firmName,
        tradeName,
        integrationCode,
        firmType,
        isCurrent,
        customerGroup,
        email,
        priceNo,
        wholesalePriceNo,
        invoiceCompany,
        generalDiscount,
        paymentMethod,
        taxOffice,
        taxNo,
        isEInvoice,
        cargoCode,
        purchasePriceNo,
        paymentVkn,
        iban,
        notes,
      ],
    );
    res.json({ id: row.id });
  }),
);

app.patch(
  '/crm/firms/:id',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const id = req.params.id;

    const firmName = (req.body?.firmName ?? '').toString().trim();
    const tradeName = (req.body?.tradeName ?? '').toString().trim();
    const integrationCode = (req.body?.integrationCode ?? '').toString().trim();
    const firmType = (req.body?.firmType ?? '').toString().trim();
    const isCurrentRaw = req.body?.isCurrent;
    const isCurrent = typeof isCurrentRaw === 'boolean' ? isCurrentRaw : null;
    const customerGroup = (req.body?.customerGroup ?? '').toString().trim();
    const email = (req.body?.email ?? '').toString().trim();
    const priceNo = (req.body?.priceNo ?? '').toString().trim();
    const wholesalePriceNo = (req.body?.wholesalePriceNo ?? '').toString().trim();
    const invoiceCompany = (req.body?.invoiceCompany ?? '').toString().trim();
    const generalDiscount = toMoney(req.body?.generalDiscount);
    const paymentMethod = (req.body?.paymentMethod ?? '').toString().trim();
    const taxOffice = (req.body?.taxOffice ?? '').toString().trim();
    const taxNo = (req.body?.taxNo ?? '').toString().trim();
    const isEInvoiceRaw = req.body?.isEInvoice;
    const isEInvoice = typeof isEInvoiceRaw === 'boolean' ? isEInvoiceRaw : null;
    const cargoCode = (req.body?.cargoCode ?? '').toString().trim();
    const purchasePriceNo = (req.body?.purchasePriceNo ?? '').toString().trim();
    const paymentVkn = (req.body?.paymentVkn ?? '').toString().trim();
    const iban = (req.body?.iban ?? '').toString().trim();
    const notes = (req.body?.notes ?? '').toString().trim();
    const isActiveRaw = req.body?.isActive;
    const isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : null;

    const hasAny =
      firmName ||
      tradeName ||
      integrationCode ||
      firmType ||
      isCurrent != null ||
      customerGroup ||
      email ||
      priceNo ||
      wholesalePriceNo ||
      invoiceCompany ||
      generalDiscount != null ||
      paymentMethod ||
      taxOffice ||
      taxNo ||
      isEInvoice != null ||
      cargoCode ||
      purchasePriceNo ||
      paymentVkn ||
      iban ||
      notes ||
      isActive != null;
    if (!hasAny) return res.status(400).json({ error: 'NO_CHANGES' });

    const sets = [];
    const params = [id];
    const add = (sql, value) => {
      params.push(value);
      sets.push(sql.replace('?', `$${params.length}`));
    };
    if (firmName) add('firm_name = ?', firmName);
    if (tradeName) add('trade_name = ?', tradeName);
    if (integrationCode) add('integration_code = ?', integrationCode);
    if (firmType) add('firm_type = ?', firmType);
    if (isCurrent != null) add('is_current = ?', isCurrent);
    if (customerGroup) add('customer_group = ?', customerGroup);
    if (email) add('email = ?', email);
    if (priceNo) add('price_no = ?', priceNo);
    if (wholesalePriceNo) add('wholesale_price_no = ?', wholesalePriceNo);
    if (invoiceCompany) add('invoice_company = ?', invoiceCompany);
    if (generalDiscount != null) add('general_discount = ?::numeric', generalDiscount);
    if (paymentMethod) add('payment_method = ?', paymentMethod);
    if (taxOffice) add('tax_office = ?', taxOffice);
    if (taxNo) add('tax_no = ?', taxNo);
    if (isEInvoice != null) add('is_einvoice = ?', isEInvoice);
    if (cargoCode) add('cargo_code = ?', cargoCode);
    if (purchasePriceNo) add('purchase_price_no = ?', purchasePriceNo);
    if (paymentVkn) add('payment_vkn = ?', paymentVkn);
    if (iban) add('iban = ?', iban);
    if (notes) add('notes = ?', notes);
    if (isActive != null) add('is_active = ?', isActive);
    sets.push('updated_at = now()');

    await pool.query(`update crm_firms set ${sets.join(', ')} where id = $1::uuid`, params);
    res.json({ ok: true });
  }),
);

app.get(
  '/sales/daily',
  authRequired,
  asyncRoute(async (req, res) => {
  const branchId = (req.query?.branchId ?? '').toString().trim();
  const date = asDateString(req.query?.date);
  if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
  if (!date) return res.status(400).json({ error: 'DATE_REQUIRED' });

  const row = await queryOne(
    `
    select gross_total as total
    from daily_sales
    where branch_id = $1 and business_date = $2::date
    limit 1
    `,
    [branchId, date],
  );

  res.json({ total: row?.total ?? 0 });
  }),
);

app.get(
  '/pos/pull/status',
  authRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim() || null;
    const rows = await queryAll(
      `
      with
        s as (
          select
            branch_id,
            max(updated_at) as last_pulled_at,
            max(business_date) as last_business_date
          from pos_register_daily_sales
          where source = 'pos'
          group by branch_id
        ),
        p as (
          select
            branch_id,
            max(updated_at) as last_pulled_at,
            max(business_date) as last_business_date
          from pos_register_daily_payments
          where source = 'pos'
          group by branch_id
        ),
        pr as (
          select
            branch_id,
            max(updated_at) as last_pulled_at,
            max(business_date) as last_business_date
          from pos_register_daily_product_sales
          where source = 'pos'
          group by branch_id
        ),
        a as (
          select
            branch_id,
            max(updated_at) as last_pulled_at,
            max(business_date) as last_business_date
          from pos_register_daily_adjustments
          where source = 'pos'
          group by branch_id
        ),
        g as (
          select
            branch_id,
            max(updated_at) as last_pulled_at,
            max(business_date) as last_business_date
          from pos_register_daily_sales_groups
          where source = 'pos'
          group by branch_id
        )
      select
        b.id as "branchId",
        b.name as "branchName",
        b.is_active as "isActive",
        nullif(
          greatest(
            coalesce(s.last_pulled_at, 'epoch'::timestamptz),
            coalesce(p.last_pulled_at, 'epoch'::timestamptz),
            coalesce(pr.last_pulled_at, 'epoch'::timestamptz),
            coalesce(a.last_pulled_at, 'epoch'::timestamptz),
            coalesce(g.last_pulled_at, 'epoch'::timestamptz)
          ),
          'epoch'::timestamptz
        ) as "lastPulledAt",
        nullif(
          greatest(
            coalesce(s.last_business_date, '1970-01-01'::date),
            coalesce(p.last_business_date, '1970-01-01'::date),
            coalesce(pr.last_business_date, '1970-01-01'::date),
            coalesce(a.last_business_date, '1970-01-01'::date),
            coalesce(g.last_business_date, '1970-01-01'::date)
          ),
          '1970-01-01'::date
        ) as "lastBusinessDate"
      from branches b
      left join s on s.branch_id = b.id
      left join p on p.branch_id = b.id
      left join pr on pr.branch_id = b.id
      left join a on a.branch_id = b.id
      left join g on g.branch_id = b.id
      where b.is_active = true
        and ($1::uuid is null or b.id = $1::uuid)
      order by b.name asc
      `,
      [branchId],
    );
    res.json(rows);
  }),
);

app.get(
  '/sales/daily/registers',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    const date = asDateString(req.query?.date);
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!date) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const rows = await queryAll(
      `
      select register_code as "registerCode", gross_total as "grossTotal"
      from pos_register_daily_sales
      where branch_id = $1::uuid and business_date = $2::date and source='pos'
      order by register_code asc
      `,
      [branchId, date],
    );

    res.json(rows);
  }),
);

app.get(
  '/sales/daily/payments',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    const date = asDateString(req.query?.date);
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!date) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const rows = await queryAll(
      `
      select
        register_code as "registerCode",
        payment_code as "paymentCode",
        amount
      from pos_register_daily_payments
      where branch_id = $1::uuid and business_date = $2::date and source='pos'
      order by register_code asc, payment_code asc
      `,
      [branchId, date],
    );

    res.json(rows);
  }),
);

app.get(
  '/sales/daily/products',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    const date = asDateString(req.query?.date);
    const registerCodeRaw = (req.query?.registerCode ?? '').toString().trim();
    const registerCode = registerCodeRaw ? registerCodeRaw : null;
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!date) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const rows = await queryAll(
      `
      select
        product_code as "productCode",
        max(coalesce(product_name,'')) as "productName",
        coalesce(sum(quantity),0) as quantity,
        coalesce(sum(gross_total),0) as "grossTotal"
      from pos_register_daily_product_sales
      where
        branch_id = $1::uuid
        and business_date = $2::date
        and source='pos'
        and ($3::text is null or register_code = $3::text)
      group by product_code
      order by coalesce(sum(gross_total),0) desc, product_code asc
      limit 200
      `,
      [branchId, date, registerCode],
    );
    res.json(rows);
  }),
);

app.get(
  '/sales/daily/adjustments',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    const date = asDateString(req.query?.date);
    const registerCodeRaw = (req.query?.registerCode ?? '').toString().trim();
    const registerCode = registerCodeRaw ? registerCodeRaw : null;
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!date) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const rows = await queryAll(
      `
      select
        kind,
        coalesce(sum(amount),0) as amount,
        coalesce(sum(count),0)::int as count
      from pos_register_daily_adjustments
      where
        branch_id = $1::uuid
        and business_date = $2::date
        and source='pos'
        and ($3::text is null or register_code = $3::text)
      group by kind
      order by kind asc
      `,
      [branchId, date, registerCode],
    );

    res.json(rows);
  }),
);

app.get(
  '/sales/daily/groups',
  authRequired,
  asyncRoute(async (req, res) => {
    const branchId = (req.query?.branchId ?? '').toString().trim();
    const date = asDateString(req.query?.date);
    const registerCodeRaw = (req.query?.registerCode ?? '').toString().trim();
    const registerCode = registerCodeRaw ? registerCodeRaw : null;
    if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
    if (!date) return res.status(400).json({ error: 'DATE_REQUIRED' });
    if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const rows = await queryAll(
      `
      select
        group_code as "groupCode",
        coalesce(sum(order_count),0)::int as "orderCount",
        coalesce(sum(gross_total),0) as "grossTotal"
      from pos_register_daily_sales_groups
      where
        branch_id = $1::uuid
        and business_date = $2::date
        and source='pos'
        and ($3::text is null or register_code = $3::text)
      group by group_code
      order by group_code asc
      `,
      [branchId, date, registerCode],
    );

    res.json(rows);
  }),
);

function posAuthRequired(req, res, next) {
  const headerSecret = (req.headers['x-pos-secret'] ?? '').toString().trim();
  const envSecret = (process.env.POS_SECRET ?? '').toString().trim();
  if (envSecret && headerSecret && headerSecret === envSecret) {
    req.user = {
      sub: 'pos',
      role: 'accounting',
      branchId: null,
    };
    return next();
  }
  return authRequired(req, res, next);
}

function cronJobAuthRequired(req, res, next) {
  const cronSecret = (process.env.CRON_SECRET ?? '').toString().trim();
  const authHeader = (req.headers.authorization ?? '').toString().trim();
  if (cronSecret && authHeader === `Bearer ${cronSecret}`) {
    req.user = {
      sub: 'cron',
      role: 'accounting',
      branchId: null,
    };
    return next();
  }

  if (!cronSecret) {
    const vercelCronHeader = (req.headers['x-vercel-cron'] ?? '').toString().trim();
    const ua = (req.headers['user-agent'] ?? '').toString();
    const isVercelCron = vercelCronHeader === '1' || ua.includes('vercel-cron/1.0');
    if (isVercelCron) {
      req.user = {
        sub: 'cron',
        role: 'accounting',
        branchId: null,
      };
      return next();
    }
  }

  return authRequired(req, res, next);
}

app.post(
  '/pos/import/daily',
  posAuthRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const body = req.body ?? {};
    const payload = body?.payload ?? body;

    const defaultBranchId = (body?.branchId ?? '').toString().trim() || null;
    const defaultBranchCode = (body?.branchCode ?? '').toString().trim() || null;
    const defaultBusinessDate = asDateString(body?.businessDate ?? body?.date) || null;
    const defaultSource = (body?.source ?? 'pos').toString().trim() || 'pos';

    const normalized = [];

    const asString = (v) => (v ?? '').toString().trim();
    const pickDate = (v) => asDateString(v) || null;
    const isObj = (v) => v && typeof v === 'object' && !Array.isArray(v);

    const pushRegister = (raw, inherited) => {
      if (!isObj(raw)) return;
      const branchId = asString(raw.branchId) || inherited.branchId || defaultBranchId;
      const branchCode = asString(raw.branchCode) || asString(raw.branch?.code) || inherited.branchCode || defaultBranchCode;
      const businessDate =
        pickDate(raw.businessDate) ||
        pickDate(raw.date) ||
        pickDate(inherited.businessDate) ||
        defaultBusinessDate;
      const source = asString(raw.source) || inherited.source || defaultSource;

      const registerCode =
        asString(raw.registerCode) ||
        asString(raw.register) ||
        asString(raw.cashRegisterCode) ||
        asString(raw.kasaKodu) ||
        asString(raw.kasaCode) ||
        asString(raw.kasa) ||
        '';

      const grossTotal =
        toMoney(raw.grossTotal) ??
        toMoney(raw.total) ??
        toMoney(raw.ciro);

      const paymentsRaw = raw.payments ?? raw.paymentLines ?? raw.paymentTotals ?? null;
      let payments = [];
      if (Array.isArray(paymentsRaw)) {
        payments = paymentsRaw;
      } else if (isObj(paymentsRaw)) {
        payments = Object.entries(paymentsRaw).map(([paymentCode, amount]) => ({ paymentCode, amount }));
      }

      const productsRaw = raw.products ?? raw.productSales ?? raw.items ?? null;
      const products = Array.isArray(productsRaw) ? productsRaw : [];

      if (!businessDate || !registerCode) return;
      normalized.push({
        branchId: branchId || null,
        branchCode: branchCode || null,
        businessDate,
        registerCode,
        grossTotal,
        source,
        payments,
        products,
      });
    };

    const pushDay = (raw) => {
      if (!isObj(raw)) return;
      const inherited = {
        branchId: asString(raw.branchId) || asString(raw.branch?.id) || defaultBranchId,
        branchCode: asString(raw.branchCode) || asString(raw.branch?.code) || defaultBranchCode,
        businessDate: pickDate(raw.businessDate) || pickDate(raw.date) || defaultBusinessDate,
        source: asString(raw.source) || defaultSource,
      };

      const registersRaw = raw.registers ?? raw.cashRegisters ?? raw.kasalar ?? raw.posRegisters ?? null;
      if (Array.isArray(registersRaw)) {
        for (const r of registersRaw) pushRegister(r, inherited);
        return;
      }
      if (isObj(registersRaw)) {
        for (const [code, v] of Object.entries(registersRaw)) {
          if (isObj(v)) {
            pushRegister({ registerCode: code, ...v }, inherited);
          } else {
            pushRegister({ registerCode: code, grossTotal: v }, inherited);
          }
        }
        return;
      }

      pushRegister(raw, inherited);
    };

    if (Array.isArray(payload)) {
      for (const row of payload) pushDay(row);
    } else if (isObj(payload)) {
      const branchesRaw =
        payload.branches ?? payload.branchList ?? payload.subeler ?? payload.subelerList ?? null;
      if (Array.isArray(branchesRaw)) {
        for (const b of branchesRaw) pushDay(b);
      } else {
        const daysRaw = payload.days ?? payload.items ?? payload.data ?? payload.result ?? null;
        if (Array.isArray(daysRaw)) {
          for (const d of daysRaw) pushDay(d);
        } else {
          pushDay(payload);
        }
      }
    }

    if (normalized.length === 0) return res.status(400).json({ error: 'ITEMS_REQUIRED' });

    const client = await pool.connect();
    try {
      await client.query('begin');

      const affectedRegistersFromProducts = new Set();
      const affectedDays = new Set();

      const resolveBranchId = async (branchIdRaw, branchCodeRaw) => {
        const bid = (branchIdRaw ?? '').toString().trim();
        if (bid) return bid;
        const bcode = (branchCodeRaw ?? '').toString().trim();
        if (!bcode) return '';
        const b = await client.query(`select id from branches where lower(code) = lower($1) limit 1`, [bcode]);
        return b.rows?.[0]?.id ?? '';
      };

      for (const raw of normalized) {
        const businessDate = asDateString(raw.businessDate);
        const source = (raw.source ?? 'pos').toString().trim() || 'pos';
        const registerCode = (raw.registerCode ?? '').toString().trim();
        const branchId = await resolveBranchId(raw.branchId, raw.branchCode);
        const grossTotal = raw.grossTotal == null ? null : toMoney(raw.grossTotal);

        if (!businessDate || !branchId || !registerCode) continue;
        if (source !== 'pos') continue;

        if (grossTotal != null) {
          await client.query(
            `
            insert into pos_register_daily_sales(branch_id, business_date, register_code, gross_total, source)
            values ($1::uuid, $2::date, $3, $4::numeric, $5)
            on conflict (branch_id, business_date, source, register_code)
            do update set gross_total=excluded.gross_total, updated_at=now()
            `,
            [branchId, businessDate, registerCode, grossTotal, source],
          );
          affectedDays.add(`${branchId}|${businessDate}|${source}`);
        }

        const payments = Array.isArray(raw.payments) ? raw.payments : [];
        for (const p of payments) {
          const paymentCode = (p?.paymentCode ?? p?.code ?? '').toString().trim();
          const amount = toMoney(p?.amount ?? p?.total);
          if (!paymentCode || amount == null) continue;
          await client.query(
            `
            insert into pos_register_daily_payments(
              branch_id, business_date, register_code, payment_code, amount, source
            )
            values ($1::uuid, $2::date, $3, $4, $5::numeric, $6)
            on conflict (branch_id, business_date, source, register_code, payment_code)
            do update set amount=excluded.amount, updated_at=now()
            `,
            [branchId, businessDate, registerCode, paymentCode, amount, source],
          );
          affectedDays.add(`${branchId}|${businessDate}|${source}`);
        }

        const products = Array.isArray(raw.products) ? raw.products : [];
        for (const pr of products) {
          const productCode = (pr?.productCode ?? pr?.code ?? '').toString().trim();
          const productName = (pr?.productName ?? pr?.name ?? '').toString().trim() || null;
          const quantity = toQty(pr?.quantity ?? pr?.qty) ?? 0;
          const lineTotal = toMoney(pr?.grossTotal ?? pr?.total ?? pr?.amount) ?? 0;
          if (!productCode) continue;

          if (productName) {
            await client.query(
              `
              insert into inv_products(code, name, unit, is_active)
              values ($1, $2, 'adet', true)
              on conflict (code) do update set
                name = excluded.name,
                is_active = true,
                updated_at = now()
              `,
              [productCode, productName],
            );
          }

          await client.query(
            `
            insert into pos_register_daily_product_sales(
              branch_id, business_date, register_code, product_code, product_name, quantity, gross_total, source
            )
            values ($1::uuid, $2::date, $3, $4, $5, $6::numeric, $7::numeric, $8)
            on conflict (branch_id, business_date, source, register_code, product_code)
            do update set
              product_name = excluded.product_name,
              quantity = excluded.quantity,
              gross_total = excluded.gross_total,
              updated_at = now()
            `,
            [branchId, businessDate, registerCode, productCode, productName, quantity, lineTotal, source],
          );

          affectedRegistersFromProducts.add(`${branchId}|${businessDate}|${source}|${registerCode}`);
          affectedDays.add(`${branchId}|${businessDate}|${source}`);
        }
      }

      for (const key of affectedRegistersFromProducts.values()) {
        const [branchId, businessDate, source, registerCode] = key.split('|');
        const sumRow = await client.query(
          `
          select coalesce(sum(gross_total),0) as total
          from pos_register_daily_product_sales
          where branch_id=$1::uuid and business_date=$2::date and source=$3 and register_code=$4
          `,
          [branchId, businessDate, source, registerCode],
        );
        const total = sumRow.rows?.[0]?.total ?? 0;
        await client.query(
          `
          insert into pos_register_daily_sales(branch_id, business_date, register_code, gross_total, source)
          values ($1::uuid, $2::date, $3, $4::numeric, $5)
          on conflict (branch_id, business_date, source, register_code)
          do update set gross_total=excluded.gross_total, updated_at=now()
          `,
          [branchId, businessDate, registerCode, total, source],
        );
      }

      for (const key of affectedDays.values()) {
        const [branchId, businessDate, source] = key.split('|');
        const sumRow = await client.query(
          `
          select coalesce(sum(gross_total),0) as total
          from pos_register_daily_sales
          where branch_id=$1::uuid and business_date=$2::date and source=$3
          `,
          [branchId, businessDate, source],
        );
        const total = sumRow.rows?.[0]?.total ?? 0;
        await client.query(
          `
          insert into daily_sales(branch_id, business_date, source, gross_total)
          values ($1::uuid, $2::date, $3, $4::numeric)
          on conflict (branch_id, business_date, source)
          do update set gross_total=excluded.gross_total
          `,
          [branchId, businessDate, source, total],
        );
      }

      await client.query('commit');
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }

    res.json({ ok: true, imported: normalized.length });
  }),
);

app.post(
  '/pos/import/register-daily-sales',
  posAuthRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const items = Array.isArray(req.body?.items) ? req.body.items : null;
    if (!items || items.length === 0) return res.status(400).json({ error: 'ITEMS_REQUIRED' });

    const client = await pool.connect();
    try {
      await client.query('begin');

      for (const raw of items) {
        const businessDate = asDateString((raw?.businessDate ?? '').toString());
        const source = (raw?.source ?? 'pos').toString().trim() || 'pos';
        const registerCode = (raw?.registerCode ?? '').toString().trim();
        const grossTotal = toMoney(raw?.grossTotal);
        const branchIdRaw = (raw?.branchId ?? '').toString().trim();
        const branchCodeRaw = (raw?.branchCode ?? '').toString().trim();

        if (!businessDate || !registerCode || grossTotal == null) continue;
        if (source !== 'pos') continue;

        let branchId = branchIdRaw;
        if (!branchId && branchCodeRaw) {
          const b = await queryOne(
            `select id from branches where lower(code) = lower($1) limit 1`,
            [branchCodeRaw],
          );
          branchId = b?.id ?? '';
        }
        if (!branchId) continue;

        await client.query(
          `
          insert into pos_register_daily_sales(
            branch_id, business_date, register_code, gross_total, source
          )
          values ($1::uuid, $2::date, $3, $4::numeric, $5)
          on conflict (branch_id, business_date, source, register_code)
          do update set gross_total=excluded.gross_total, updated_at=now()
          `,
          [branchId, businessDate, registerCode, grossTotal, source],
        );

        const sumRow = await client.query(
          `
          select coalesce(sum(gross_total),0) as total
          from pos_register_daily_sales
          where branch_id=$1::uuid and business_date=$2::date and source=$3
          `,
          [branchId, businessDate, source],
        );
        const total = sumRow.rows?.[0]?.total ?? 0;

        await client.query(
          `
          insert into daily_sales(branch_id, business_date, source, gross_total)
          values ($1::uuid, $2::date, $3, $4::numeric)
          on conflict (branch_id, business_date, source)
          do update set gross_total=excluded.gross_total
          `,
          [branchId, businessDate, source, total],
        );
      }

      await client.query('commit');
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }

    res.json({ ok: true });
  }),
);

app.post(
  '/pos/import/register-daily-payments',
  posAuthRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const items = Array.isArray(req.body?.items) ? req.body.items : null;
    if (!items || items.length === 0) return res.status(400).json({ error: 'ITEMS_REQUIRED' });

    const client = await pool.connect();
    try {
      await client.query('begin');

      for (const raw of items) {
        const businessDate = asDateString((raw?.businessDate ?? '').toString());
        const source = (raw?.source ?? 'pos').toString().trim() || 'pos';
        const registerCode = (raw?.registerCode ?? '').toString().trim();
        const paymentCode = (raw?.paymentCode ?? '').toString().trim();
        const amount = toMoney(raw?.amount);
        const branchIdRaw = (raw?.branchId ?? '').toString().trim();
        const branchCodeRaw = (raw?.branchCode ?? '').toString().trim();

        if (!businessDate || !registerCode || !paymentCode || amount == null) continue;
        if (source !== 'pos') continue;

        let branchId = branchIdRaw;
        if (!branchId && branchCodeRaw) {
          const b = await queryOne(
            `select id from branches where lower(code) = lower($1) limit 1`,
            [branchCodeRaw],
          );
          branchId = b?.id ?? '';
        }
        if (!branchId) continue;

        await client.query(
          `
          insert into pos_register_daily_payments(
            branch_id, business_date, register_code, payment_code, amount, source
          )
          values ($1::uuid, $2::date, $3, $4, $5::numeric, $6)
          on conflict (branch_id, business_date, source, register_code, payment_code)
          do update set amount=excluded.amount, updated_at=now()
          `,
          [branchId, businessDate, registerCode, paymentCode, amount, source],
        );
      }

      await client.query('commit');
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }

    res.json({ ok: true });
  }),
);

app.post(
  '/pos/import/register-daily-product-sales',
  posAuthRequired,
  requireAnyRole(['manager', 'accounting']),
  asyncRoute(async (req, res) => {
    const items = Array.isArray(req.body?.items) ? req.body.items : null;
    if (!items || items.length === 0) return res.status(400).json({ error: 'ITEMS_REQUIRED' });

    const client = await pool.connect();
    try {
      await client.query('begin');

      const affectedRegisters = new Set();
      const affectedDays = new Set();

      for (const raw of items) {
        const businessDate = asDateString((raw?.businessDate ?? '').toString());
        const source = (raw?.source ?? 'pos').toString().trim() || 'pos';
        const registerCode = (raw?.registerCode ?? '').toString().trim();
        const productCode = (raw?.productCode ?? '').toString().trim();
        const productName = (raw?.productName ?? '').toString().trim() || null;
        const quantity = toQty(raw?.quantity) ?? 0;
        const grossTotal = toMoney(raw?.grossTotal) ?? 0;
        const branchIdRaw = (raw?.branchId ?? '').toString().trim();
        const branchCodeRaw = (raw?.branchCode ?? '').toString().trim();

        if (!businessDate || !registerCode || !productCode) continue;
        if (source !== 'pos') continue;

        let branchId = branchIdRaw;
        if (!branchId && branchCodeRaw) {
          const b = await client.query(
            `select id from branches where lower(code) = lower($1) limit 1`,
            [branchCodeRaw],
          );
          branchId = b.rows?.[0]?.id ?? '';
        }
        if (!branchId) continue;

        if (productName) {
          await client.query(
            `
            insert into inv_products(code, name, unit, is_active)
            values ($1, $2, 'adet', true)
            on conflict (code) do update set
              name = excluded.name,
              is_active = true,
              updated_at = now()
            `,
            [productCode, productName],
          );
        }

        await client.query(
          `
          insert into pos_register_daily_product_sales(
            branch_id, business_date, register_code, product_code, product_name, quantity, gross_total, source
          )
          values ($1::uuid, $2::date, $3, $4, $5, $6::numeric, $7::numeric, $8)
          on conflict (branch_id, business_date, source, register_code, product_code)
          do update set
            product_name = excluded.product_name,
            quantity = excluded.quantity,
            gross_total = excluded.gross_total,
            updated_at = now()
          `,
          [branchId, businessDate, registerCode, productCode, productName, quantity, grossTotal, source],
        );

        affectedRegisters.add(`${branchId}|${businessDate}|${source}|${registerCode}`);
        affectedDays.add(`${branchId}|${businessDate}|${source}`);
      }

      for (const key of affectedRegisters.values()) {
        const [branchId, businessDate, source, registerCode] = key.split('|');
        const sumRow = await client.query(
          `
          select coalesce(sum(gross_total),0) as total
          from pos_register_daily_product_sales
          where branch_id=$1::uuid and business_date=$2::date and source=$3 and register_code=$4
          `,
          [branchId, businessDate, source, registerCode],
        );
        const total = sumRow.rows?.[0]?.total ?? 0;
        await client.query(
          `
          insert into pos_register_daily_sales(branch_id, business_date, register_code, gross_total, source)
          values ($1::uuid, $2::date, $3, $4::numeric, $5)
          on conflict (branch_id, business_date, source, register_code)
          do update set gross_total=excluded.gross_total, updated_at=now()
          `,
          [branchId, businessDate, registerCode, total, source],
        );
      }

      for (const key of affectedDays.values()) {
        const [branchId, businessDate, source] = key.split('|');
        const sumRow = await client.query(
          `
          select coalesce(sum(gross_total),0) as total
          from pos_register_daily_sales
          where branch_id=$1::uuid and business_date=$2::date and source=$3
          `,
          [branchId, businessDate, source],
        );
        const total = sumRow.rows?.[0]?.total ?? 0;
        await client.query(
          `
          insert into daily_sales(branch_id, business_date, source, gross_total)
          values ($1::uuid, $2::date, $3, $4::numeric)
          on conflict (branch_id, business_date, source)
          do update set gross_total=excluded.gross_total
          `,
          [branchId, businessDate, source, total],
        );
      }

      await client.query('commit');
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }

    res.json({ ok: true });
  }),
);

function canAccessBranch(req, branchId) {
  if (req.user?.role === 'manager' || req.user?.role === 'accounting') return true;
  return req.user?.branchId === branchId;
}

app.get(
  '/cash-reconciliations',
  authRequired,
  asyncRoute(async (req, res) => {
  const from = asDateString(req.query?.from);
  const to = asDateString(req.query?.to);
  const branchId = (req.query?.branchId ?? '').toString().trim() || null;
  const status = (req.query?.status ?? '').toString().trim() || null;

  if (branchId && !canAccessBranch(req, branchId)) {
    return res.status(403).json({ error: 'FORBIDDEN' });
  }

  const filters = [];
  const params = [];
  const add = (sql, value) => {
    params.push(value);
    filters.push(sql.replace('?', `$${params.length}`));
  };

  if (from) add('r.business_date >= ?::date', from);
  if (to) add('r.business_date <= ?::date', to);
  if (branchId) add('r.branch_id = ?::uuid', branchId);
  if (status) add('r.status = ?', status);

  if (req.user?.role === 'branchUser') {
    add('r.branch_id = ?::uuid', req.user.branchId);
  }

  const where = filters.length ? `where ${filters.join(' and ')}` : '';

  const rows = await queryAll(
    `
    with payment_totals as (
      select reconciliation_id, coalesce(sum(amount),0) as payment_total
      from cash_reconciliation_payment_lines
      group by reconciliation_id
    ),
    card_types as (
      select id
      from payment_types
      where (
        lower(name) like '%kredi%' or
        lower(name) like '%kart%' or
        lower(code) like '%card%' or
        lower(code) like '%kredi%' or
        lower(code) like '%kk%'
      )
      and lower(name) not like '%fast%'
      and lower(code) not like '%fast%'
    ),
    manual_card_totals as (
      select pl.reconciliation_id, coalesce(sum(pl.amount),0) as manual_card_total
      from cash_reconciliation_payment_lines pl
      join card_types ct on ct.id = pl.payment_type_id
      group by pl.reconciliation_id
    ),
    attachment_info as (
      select
        reconciliation_id,
        count(*)::int as attachments_count,
        bool_or(kind = 'countSlip') as has_count_slip,
        bool_or(kind = 'signedStatement') as has_signed_statement
      from cash_reconciliation_attachments
      group by reconciliation_id
    ),
    latest_eod as (
      select distinct on (reconciliation_id)
        reconciliation_id,
        card_total,
        fast_total,
        created_at
      from pos_end_of_day_reports
      order by reconciliation_id, created_at desc
    )
    select
      r.id,
      r.branch_id as "branchId",
      r.business_date as "businessDate",
      r.expected_sales_total as "expectedSalesTotal",
      r.status,
      r.created_by_user_id as "createdByUserId",
      r.approved_by_user_id as "approvedByUserId",
      r.rejection_reason as "rejectionReason",
      coalesce(pt.payment_total,0) as "paymentTotal",
      (coalesce(pt.payment_total,0) - r.expected_sales_total) as "difference",
      coalesce(ai.attachments_count,0) as "attachmentsCount",
      coalesce(ai.has_count_slip,false) as "hasCountSlip",
      coalesce(ai.has_signed_statement,false) as "hasSignedStatement",
      coalesce(le.card_total,0) as "ocrCardTotal",
      coalesce(le.fast_total,0) as "ocrFastTotal",
      (le.reconciliation_id is not null) as "hasEndOfDayReport",
      coalesce(mct.manual_card_total,0) as "manualCardTotal"
    from cash_reconciliations r
    left join payment_totals pt on pt.reconciliation_id = r.id
    left join attachment_info ai on ai.reconciliation_id = r.id
    left join latest_eod le on le.reconciliation_id = r.id
    left join manual_card_totals mct on mct.reconciliation_id = r.id
    ${where}
    order by r.business_date desc, r.created_at desc
    limit 500
    `,
    params,
  );

  res.json(rows);
  }),
);

app.get(
  '/cash-reconciliations/:id',
  authRequired,
  asyncRoute(async (req, res) => {
  const id = req.params.id;
  const recon = await queryOne(
    `
    select
      id,
      branch_id as "branchId",
      business_date as "businessDate",
      expected_sales_total as "expectedSalesTotal",
      status,
      created_by_user_id as "createdByUserId",
      approved_by_user_id as "approvedByUserId",
      rejection_reason as "rejectionReason"
    from cash_reconciliations
    where id = $1::uuid
    `,
    [id],
  );
  if (!recon) return res.status(404).json({ error: 'NOT_FOUND' });
  if (!canAccessBranch(req, recon.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

  const paymentLines = await queryAll(
    `
    select payment_type_id as "typeId", amount
    from cash_reconciliation_payment_lines
    where reconciliation_id = $1::uuid
    order by created_at asc
    `,
    [id],
  );

  const expenseLines = await queryAll(
    `
    select expense_type_id as "typeId", amount
    from cash_reconciliation_expense_lines
    where reconciliation_id = $1::uuid
    order by created_at asc
    `,
    [id],
  );

  const attachments = await queryAll(
    `
    select id, kind, file_name as "fileName", mime_type as "mimeType", size_bytes as "sizeBytes"
    from cash_reconciliation_attachments
    where reconciliation_id = $1::uuid
    order by created_at asc
    `,
    [id],
  );

  res.json({ ...recon, paymentLines, expenseLines, attachments });
  }),
);

app.post(
  '/cash-reconciliations',
  authRequired,
  asyncRoute(async (req, res) => {
  const branchId = (req.body?.branchId ?? '').toString().trim();
  const businessDate = asDateString(req.body?.businessDate);
  if (!branchId) return res.status(400).json({ error: 'BRANCH_REQUIRED' });
  if (!businessDate) return res.status(400).json({ error: 'DATE_REQUIRED' });
  if (!canAccessBranch(req, branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

  const createdByUserId = req.user.sub;

  const row = await queryOne(
    `
    insert into cash_reconciliations(branch_id, business_date, expected_sales_total, created_by_user_id)
    values (
      $1::uuid,
      $2::date,
      coalesce(
        (select gross_total from daily_sales where branch_id = $1 and business_date = $2::date limit 1),
        0
      ),
      $3::uuid
    )
    on conflict (branch_id, business_date)
    do update set updated_at = now()
    returning id
    `,
    [branchId, businessDate, createdByUserId],
  );

  res.json({ id: row.id });
  }),
);

app.patch(
  '/cash-reconciliations/:id',
  authRequired,
  asyncRoute(async (req, res) => {
  const id = req.params.id;
  const recon = await queryOne(
    `select id, branch_id as "branchId", status, created_by_user_id as "createdByUserId" from cash_reconciliations where id=$1::uuid`,
    [id],
  );
  if (!recon) return res.status(404).json({ error: 'NOT_FOUND' });
  if (!canAccessBranch(req, recon.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

  const isManager = req.user.role === 'manager';
  const isOwner = req.user.sub === recon.createdByUserId;
  const canEdit =
    isManager || (isOwner && (recon.status === 'draft' || recon.status === 'rejected'));
  if (!canEdit) return res.status(403).json({ error: 'FORBIDDEN' });

  const expected = toMoney(req.body?.expectedSalesTotal);
  const paymentLines = Array.isArray(req.body?.paymentLines) ? req.body.paymentLines : null;
  const expenseLines = Array.isArray(req.body?.expenseLines) ? req.body.expenseLines : null;

  const client = await pool.connect();
  try {
    await client.query('begin');

    if (expected != null) {
      await client.query(
        `update cash_reconciliations set expected_sales_total=$2::numeric, updated_at=now() where id=$1::uuid`,
        [id, expected],
      );
    }

    if (paymentLines) {
      await client.query(
        `delete from cash_reconciliation_payment_lines where reconciliation_id=$1::uuid`,
        [id],
      );
      for (const line of paymentLines) {
        const typeId = (line?.typeId ?? line?.paymentTypeId ?? '').toString().trim();
        const amount = toMoney(line?.amount);
        if (!typeId || amount == null) continue;
        await client.query(
          `
          insert into cash_reconciliation_payment_lines(reconciliation_id, payment_type_id, amount)
          values ($1::uuid, $2::uuid, $3::numeric)
          `,
          [id, typeId, amount],
        );
      }
    }

    if (expenseLines) {
      await client.query(
        `delete from cash_reconciliation_expense_lines where reconciliation_id=$1::uuid`,
        [id],
      );
      for (const line of expenseLines) {
        const typeId = (line?.typeId ?? line?.expenseTypeId ?? '').toString().trim();
        const amount = toMoney(line?.amount);
        if (!typeId || amount == null) continue;
        await client.query(
          `
          insert into cash_reconciliation_expense_lines(reconciliation_id, expense_type_id, amount)
          values ($1::uuid, $2::uuid, $3::numeric)
          `,
          [id, typeId, amount],
        );
      }
    }

    await client.query(
      `insert into cash_reconciliation_audit(reconciliation_id, actor_user_id, action, notes)
       values ($1::uuid, $2::uuid, $3, $4)`,
      [id, req.user.sub, 'update', null],
    );

    await client.query('commit');
  } catch (e) {
    await client.query('rollback');
    throw e;
  } finally {
    client.release();
  }

  res.json({ ok: true });
  }),
);

app.post(
  '/cash-reconciliations/:id/submit',
  authRequired,
  asyncRoute(async (req, res) => {
  const id = req.params.id;
  const recon = await queryOne(
    `select id, branch_id as "branchId", status, created_by_user_id as "createdByUserId" from cash_reconciliations where id=$1::uuid`,
    [id],
  );
  if (!recon) return res.status(404).json({ error: 'NOT_FOUND' });
  if (!canAccessBranch(req, recon.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

  const isOwner = req.user.sub === recon.createdByUserId;
  if (!isOwner) return res.status(403).json({ error: 'FORBIDDEN' });
  if (!(recon.status === 'draft' || recon.status === 'rejected')) {
    return res.status(400).json({ error: 'INVALID_STATUS' });
  }

  const totals = await queryOne(
    `
    select
      r.expected_sales_total as expected,
      coalesce(sum(pl.amount),0) as payment_total
    from cash_reconciliations r
    left join cash_reconciliation_payment_lines pl on pl.reconciliation_id = r.id
    where r.id = $1::uuid
    group by r.expected_sales_total
    `,
    [id],
  );
  const expected = Number(totals?.expected ?? 0);
  const paymentTotal = Number(totals?.payment_total ?? 0);
  const diff = paymentTotal - expected;
  const hasDiff = Number.isFinite(diff) && Math.abs(diff) > 0.01;
  if (hasDiff) {
    const a = await queryOne(
      `
      select
        bool_or(kind = 'countSlip') as has_count_slip,
        bool_or(kind = 'signedStatement') as has_signed_statement
      from cash_reconciliation_attachments
      where reconciliation_id = $1::uuid
      `,
      [id],
    );
    const missing = [];
    if (!a?.has_count_slip) missing.push('countSlip');
    if (!a?.has_signed_statement) missing.push('signedStatement');
    if (missing.length) {
      return res.status(400).json({ error: 'MISSING_ATTACHMENTS', missing });
    }
  }

  await pool.query(
    `update cash_reconciliations set status='submitted', updated_at=now() where id=$1::uuid`,
    [id],
  );

  await pool.query(
    `insert into cash_reconciliation_audit(reconciliation_id, actor_user_id, action)
     values ($1::uuid, $2::uuid, $3)`,
    [id, req.user.sub, 'submit'],
  );

  res.json({ ok: true });
  }),
);

app.post(
  '/cash-reconciliations/:id/approve',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
  const id = req.params.id;
  const recon = await queryOne(
    `select id, branch_id as "branchId", status from cash_reconciliations where id=$1::uuid`,
    [id],
  );
  if (!recon) return res.status(404).json({ error: 'NOT_FOUND' });
  if (!canAccessBranch(req, recon.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });
  if (recon.status !== 'submitted') return res.status(400).json({ error: 'INVALID_STATUS' });

  const totals = await queryOne(
    `
    select
      r.expected_sales_total as expected,
      coalesce(sum(pl.amount),0) as payment_total
    from cash_reconciliations r
    left join cash_reconciliation_payment_lines pl on pl.reconciliation_id = r.id
    where r.id = $1::uuid
    group by r.expected_sales_total
    `,
    [id],
  );
  const expected = Number(totals?.expected ?? 0);
  const paymentTotal = Number(totals?.payment_total ?? 0);
  const diff = paymentTotal - expected;
  const hasDiff = Number.isFinite(diff) && Math.abs(diff) > 0.01;
  if (hasDiff) {
    const a = await queryOne(
      `
      select
        bool_or(kind = 'countSlip') as has_count_slip,
        bool_or(kind = 'signedStatement') as has_signed_statement
      from cash_reconciliation_attachments
      where reconciliation_id = $1::uuid
      `,
      [id],
    );
    const missing = [];
    if (!a?.has_count_slip) missing.push('countSlip');
    if (!a?.has_signed_statement) missing.push('signedStatement');
    if (missing.length) {
      return res.status(400).json({ error: 'MISSING_ATTACHMENTS', missing });
    }
  }

  await pool.query(
    `update cash_reconciliations set status='approved', approved_by_user_id=$2::uuid, rejection_reason=null, updated_at=now() where id=$1::uuid`,
    [id, req.user.sub],
  );
  await pool.query(
    `insert into cash_reconciliation_audit(reconciliation_id, actor_user_id, action)
     values ($1::uuid, $2::uuid, $3)`,
    [id, req.user.sub, 'approve'],
  );
  res.json({ ok: true });
  }),
);

app.post(
  '/cash-reconciliations/:id/reject',
  authRequired,
  requireRole('manager'),
  asyncRoute(async (req, res) => {
  const id = req.params.id;
  const reason = (req.body?.reason ?? '').toString().trim();
  if (!reason) return res.status(400).json({ error: 'REASON_REQUIRED' });

  const recon = await queryOne(
    `select id, branch_id as "branchId", status from cash_reconciliations where id=$1::uuid`,
    [id],
  );
  if (!recon) return res.status(404).json({ error: 'NOT_FOUND' });
  if (!canAccessBranch(req, recon.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });
  if (recon.status !== 'submitted') return res.status(400).json({ error: 'INVALID_STATUS' });

  await pool.query(
    `update cash_reconciliations set status='rejected', approved_by_user_id=null, rejection_reason=$2, updated_at=now() where id=$1::uuid`,
    [id, reason],
  );
  await pool.query(
    `insert into cash_reconciliation_audit(reconciliation_id, actor_user_id, action, notes)
     values ($1::uuid, $2::uuid, $3, $4)`,
    [id, req.user.sub, 'reject', reason],
  );
  res.json({ ok: true });
  }),
);

app.post(
  '/cash-reconciliations/:id/attachments',
  authRequired,
  asyncRoute(async (req, res) => {
  const id = req.params.id;
  const kind = (req.body?.kind ?? '').toString().trim();
  const fileName = (req.body?.fileName ?? '').toString().trim();
  const mimeType = (req.body?.mimeType ?? 'application/octet-stream').toString().trim();
  const sizeBytes = Number(req.body?.sizeBytes ?? 0);
  const storageKey = (req.body?.storageKey ?? '').toString().trim() || null;

  if (!kind || !fileName || !Number.isFinite(sizeBytes) || sizeBytes < 0) {
    return res.status(400).json({ error: 'INVALID_ATTACHMENT' });
  }

  const recon = await queryOne(
    `select id, branch_id as "branchId", status, created_by_user_id as "createdByUserId" from cash_reconciliations where id=$1::uuid`,
    [id],
  );
  if (!recon) return res.status(404).json({ error: 'NOT_FOUND' });
  if (!canAccessBranch(req, recon.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

  const isManager = req.user.role === 'manager';
  const isOwner = req.user.sub === recon.createdByUserId;
  const canEdit =
    isManager || (isOwner && (recon.status === 'draft' || recon.status === 'rejected'));
  if (!canEdit) return res.status(403).json({ error: 'FORBIDDEN' });

  const row = await queryOne(
    `
    insert into cash_reconciliation_attachments(
      reconciliation_id, kind, file_name, mime_type, size_bytes, storage_key, uploaded_by_user_id
    )
    values ($1::uuid, $2, $3, $4, $5::bigint, $6, $7::uuid)
    returning id
    `,
    [id, kind, fileName, mimeType, Math.trunc(sizeBytes), storageKey, req.user.sub],
  );

  await pool.query(
    `insert into cash_reconciliation_audit(reconciliation_id, actor_user_id, action, notes)
     values ($1::uuid, $2::uuid, $3, $4)`,
    [id, req.user.sub, 'attach', `${kind}:${fileName}`],
  );

  res.json({ id: row.id });
  }),
);

app.get(
  '/cash-reconciliations/:id/end-of-day-reports',
  authRequired,
  asyncRoute(async (req, res) => {
    const id = req.params.id;
    const recon = await queryOne(
      `select id, branch_id as "branchId" from cash_reconciliations where id=$1::uuid`,
      [id],
    );
    if (!recon) return res.status(404).json({ error: 'NOT_FOUND' });
    if (!canAccessBranch(req, recon.branchId)) return res.status(403).json({ error: 'FORBIDDEN' });

    const rows = await queryAll(
      `
      select
        id,
        business_date as "businessDate",
        report_date as "reportDate",
        merchant_title as "merchantTitle",
        workplace_no as "workplaceNo",
        terminal_no as "terminalNo",
        card_total as "cardTotal",
        fast_total as "fastTotal",
        created_at as "createdAt"
      from pos_end_of_day_reports
      where reconciliation_id = $1::uuid
      order by created_at desc
      limit 200
      `,
      [id],
    );
    res.json(rows);
  }),
);

app.post(
  '/cash-reconciliations/:id/end-of-day/card-from-image',
  authRequired,
  _upload.single('file'),
  asyncRoute(async (req, res) => {
    const requestId = crypto.randomUUID();
    const id = req.params.id;
    try {
      const recon = await queryOne(
        `
        select
          id,
          branch_id as "branchId",
          business_date as "businessDate",
          status,
          created_by_user_id as "createdByUserId"
        from cash_reconciliations
        where id=$1::uuid
        `,
        [id],
      );
      if (!recon) return res.status(404).json({ error: 'NOT_FOUND', requestId });
      if (!canAccessBranch(req, recon.branchId)) return res.status(403).json({ error: 'FORBIDDEN', requestId });

      const isManager = req.user.role === 'manager';
      const isOwner = req.user.sub === recon.createdByUserId;
      const canEdit = isManager || (isOwner && (recon.status === 'draft' || recon.status === 'rejected'));
      if (!canEdit) return res.status(403).json({ error: 'FORBIDDEN', requestId });

      const file = req.file ?? null;
      if (!file?.buffer?.length) return res.status(400).json({ error: 'FILE_REQUIRED', requestId });

      const expectedDate = asDateString(_normalizeDateValue(recon.businessDate));
      if (!expectedDate) return res.status(400).json({ error: 'DATE_REQUIRED', requestId });

      let text = '';
      try {
        const worker = await _ensureOcrWorker();
        const ocr = await worker.recognize(file.buffer);
        text = (ocr?.data?.text ?? '').toString();
      } catch (e) {
        const msg = (e?.message ?? String(e)).toString().slice(0, 200);
        return res.status(500).json({ error: 'OCR_FAILED', requestId, message: msg || null });
      }

      const parsed = _parseEndOfDayFromOcr(text);
      if (!parsed.reportDate) {
        return res.status(400).json({ error: 'DATE_NOT_FOUND', requestId });
      }
      if (!_sameDateString(parsed.reportDate, expectedDate)) {
        return res.status(400).json({
          error: 'DATE_MISMATCH',
          expectedDate,
          reportDate: parsed.reportDate,
          requestId,
        });
      }

      const workplaceNo = (parsed.workplaceNo ?? '').toString().trim() || null;
      const terminalNo = (parsed.terminalNo ?? '').toString().trim() || null;
      if (workplaceNo || terminalNo) {
        const dup = await queryOne(
          `
          select
            id,
            branch_id as "branchId",
            reconciliation_id as "reconciliationId"
          from pos_end_of_day_reports
          where report_date = $1::date
            and (
              ($2::text is not null and $3::text is not null and workplace_no = $2 and terminal_no = $3)
              or ($2::text is not null and $3::text is null and workplace_no = $2)
              or ($2::text is null and $3::text is not null and terminal_no = $3)
            )
          order by created_at desc
          limit 1
          `,
          [expectedDate, workplaceNo, terminalNo],
        );
        if (dup && dup.branchId !== recon.branchId) {
          return res.status(409).json({
            error: 'EOD_ALREADY_USED',
            reportDate: expectedDate,
            existingBranchId: dup.branchId,
            requestId,
          });
        }
      }

      const cardTotal = Number.isFinite(parsed.cardTotal) ? parsed.cardTotal : 0;
      const fastTotal = Number.isFinite(parsed.fastTotal) ? parsed.fastTotal : 0;
      const row = await queryOne(
        `
        insert into pos_end_of_day_reports(
          reconciliation_id,
          branch_id,
          business_date,
          report_date,
          merchant_title,
          workplace_no,
          terminal_no,
          card_total,
          fast_total,
          raw_text,
          created_by_user_id
        )
        values ($1::uuid,$2::uuid,$3::date,$4::date,$5,$6,$7,$8::numeric,$9::numeric,$10,$11::uuid)
        returning id
        `,
        [
          id,
          recon.branchId,
          expectedDate,
          expectedDate,
          parsed.merchantTitle,
          parsed.workplaceNo,
          parsed.terminalNo,
          cardTotal,
          fastTotal,
          text.slice(0, 20000),
          req.user.sub,
        ],
      );

      res.json({
        ok: true,
        id: row.id,
        businessDate: expectedDate,
        reportDate: expectedDate,
        merchantTitle: parsed.merchantTitle,
        workplaceNo: parsed.workplaceNo,
        terminalNo: parsed.terminalNo,
        cardTotal,
        fastTotal,
      });
    } catch (e) {
      process.stderr.write(
        JSON.stringify(
          {
            requestId,
            message: e?.message ?? String(e),
            code: e?.code ?? null,
            path: req?.path ?? null,
          },
          null,
          2,
        ) + '\n',
      );
      return res.status(500).json({ error: 'OCR_INTERNAL', requestId });
    }
  }),
);

app.use((err, req, res, next) => {
  const requestId = crypto.randomUUID();
  process.stderr.write(
    JSON.stringify(
      {
        requestId,
        message: err?.message ?? String(err),
        code: err?.code ?? null,
        path: req?.path ?? null,
      },
      null,
      2,
    ) + '\n',
  );

  if (err?.name === 'MulterError') {
    if (err?.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ error: 'FILE_TOO_LARGE', requestId });
    }
    return res.status(400).json({ error: 'UPLOAD_FAILED', requestId });
  }

  if (err?.code === '28P01') {
    return res.status(503).json({ error: 'DB_AUTH_FAILED', requestId });
  }

  if (err?.code === '42P01') {
    return res.status(503).json({ error: 'DB_SCHEMA_MISSING', requestId });
  }

  if (err?.code === '42703') {
    return res.status(503).json({ error: 'DB_SCHEMA_OUTDATED', requestId });
  }

  if (err?.code === 'ECONNREFUSED' || err?.code === 'ETIMEDOUT') {
    return res.status(503).json({ error: 'DB_UNREACHABLE', requestId });
  }

  if (err?.code === '23505') {
    return res.status(409).json({ error: 'CONFLICT', requestId });
  }

  if (err?.code === '22P02') {
    return res.status(400).json({ error: 'INVALID_INPUT', requestId });
  }

  if (err?.code === '23503') {
    return res.status(400).json({ error: 'FK_VIOLATION', requestId });
  }

  const path = (req?.path ?? '').toString();
  if (path.includes('/end-of-day/card-from-image')) {
    const msg = (err?.message ?? '').toString().slice(0, 200);
    return res.status(500).json({ error: 'OCR_INTERNAL', requestId, message: msg || null });
  }

  return res.status(500).json({ error: 'INTERNAL', requestId });
});

let _initPromise = null;
async function _ensureInit({ allowPrompt }) {
  if (_initPromise) return _initPromise;
  _initPromise = (async () => {
  const {
    PGHOST,
    PGPORT,
    PGUSER,
    PGPASSWORD,
    PGDATABASE,
    JWT_SECRET,
    CORS_ORIGIN,
    APPLY_SCHEMA,
  } = process.env;

  const requiredEnv = ['PGHOST', 'PGPORT', 'PGUSER', 'PGDATABASE'];
  const missing = requiredEnv.filter((k) => !(process.env[k] ?? '').trim());
  if (missing.length) {
    throw new Error(`Missing env vars: ${missing.join(', ')}`);
  }

  let password = (PGPASSWORD ?? '').toString();
  if (!password.trim()) {
    if (allowPrompt) {
      password = await promptSecret('PG şifre: ');
    } else {
      throw new Error('Missing env vars: PGPASSWORD');
    }
  }

  jwtSecret = (JWT_SECRET ?? '').toString().trim();
  if (!jwtSecret) {
    jwtSecret = crypto.randomBytes(48).toString('base64url');
    process.stdout.write(
      'JWT_SECRET verilmedi; bu çalıştırma için geçici bir secret üretildi (restart sonrası tokenlar geçersiz olur).\n',
    );
  }
  pool = new pg.Pool({
    host: PGHOST,
    port: Number(PGPORT),
    user: PGUSER,
    password,
    database: PGDATABASE,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 15_000,
  });

  try {
    await pool.query('select 1 as ok');
  } catch (e) {
    if (e?.code === '28P01') {
      process.stderr.write(
        'DB bağlantısı reddedildi: şifre hatalı (PGPASSWORD / kullanıcı / pg_hba). PGPASSWORD doğru mu?\n',
      );
    } else if (e?.code === 'ECONNREFUSED' || e?.code === 'ETIMEDOUT') {
      process.stderr.write('DB erişilemiyor: host/port kapalı veya ağ engeli.\n');
    } else if (e?.code === 'ENOTFOUND') {
      process.stderr.write('DB host bulunamadı (DNS/host hatası).\n');
    }
    throw e;
  }

  const applySchema =
    (APPLY_SCHEMA ?? '').toString().trim() === '1' ||
    (APPLY_SCHEMA ?? '').toString().trim().toLowerCase() === 'true';
  if (applySchema && allowPrompt) {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const schemaPath = path.resolve(here, '..', 'prosmart_postgres_schema.sql');
    const sql = await fs.readFile(schemaPath, 'utf8');
    try {
      await pool.query(sql);
      process.stdout.write('DB şeması uygulandı.\n');
    } catch (e) {
      if (e?.code === '28P01') {
        process.stderr.write(
          'Şema uygulanamadı: DB şifre doğrulaması başarısız (PGPASSWORD / kullanıcı / pg_hba).\n',
        );
      }
      throw e;
    }
  }
  })();
  return _initPromise;
}

async function main() {
  await _ensureInit({ allowPrompt: true });

  const listenPort = Number(process.env.PORT || 8080);
  app.listen(listenPort, () => {
    process.stdout.write(`prosmart-server listening on :${listenPort}\n`);
  });
}

export default async function handler(req, res) {
  await _ensureInit({ allowPrompt: false });
  if (typeof req?.url === 'string' && req.url.startsWith('/api/')) {
    req.url = req.url.slice(4) || '/';
  } else if (typeof req?.url === 'string' && req.url === '/api') {
    req.url = '/';
  }
  return app(req, res);
}

const _isDirectRun = (() => {
  try {
    const self = fileURLToPath(import.meta.url);
    const entry = (process.argv?.[1] ?? '').toString();
    if (!entry) return false;
    return path.resolve(entry) === path.resolve(self);
  } catch {
    return false;
  }
})();

if (_isDirectRun) {
  await main();
}
