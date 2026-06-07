create extension if not exists pgcrypto;

create table if not exists branches (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  business_day_start_hour int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table branches
  add column if not exists business_day_start_hour int not null default 0;

create table if not exists branch_data_sources (
  branch_id uuid primary key references branches(id) on delete cascade,
  db_host text not null,
  db_port int not null default 5432,
  db_name text not null,
  db_user text not null,
  db_password_enc bytea,
  db_ssl boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_branch_data_sources_active on branch_data_sources(is_active);

create table if not exists app_users (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  display_name text not null,
  password_hash text,
  role text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists user_branch_access (
  user_id uuid not null references app_users(id) on delete cascade,
  branch_id uuid not null references branches(id) on delete cascade,
  can_reconcile boolean not null default true,
  can_approve boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, branch_id)
);

create table if not exists payment_types (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists expense_types (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists daily_sales (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  business_date date not null,
  source text not null default 'pos',
  gross_total numeric(14,2) not null,
  created_at timestamptz not null default now(),
  unique (branch_id, business_date, source)
);

create table if not exists pos_register_daily_sales (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  business_date date not null,
  register_code text not null,
  gross_total numeric(14,2) not null,
  source text not null default 'pos',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, business_date, source, register_code)
);

create index if not exists idx_pos_reg_sales_branch_date on pos_register_daily_sales(branch_id, business_date);

create table if not exists pos_register_daily_payments (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  business_date date not null,
  register_code text not null,
  payment_code text not null,
  amount numeric(14,2) not null,
  source text not null default 'pos',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, business_date, source, register_code, payment_code)
);

create index if not exists idx_pos_reg_pay_branch_date on pos_register_daily_payments(branch_id, business_date);

create table if not exists pos_register_daily_product_sales (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  business_date date not null,
  register_code text not null,
  product_code text not null,
  product_name text,
  quantity numeric(14,3) not null default 0,
  gross_total numeric(14,2) not null default 0,
  source text not null default 'pos',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, business_date, source, register_code, product_code)
);

create index if not exists idx_pos_prod_sales_branch_date on pos_register_daily_product_sales(branch_id, business_date);

create table if not exists pos_register_daily_adjustments (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  business_date date not null,
  register_code text not null,
  kind text not null,
  amount numeric(14,2) not null default 0,
  count int not null default 0,
  source text not null default 'pos',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, business_date, source, register_code, kind)
);

create index if not exists idx_pos_adj_branch_date on pos_register_daily_adjustments(branch_id, business_date);

create table if not exists pos_register_daily_sales_groups (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  business_date date not null,
  register_code text not null,
  group_code text not null,
  order_count int not null default 0,
  gross_total numeric(14,2) not null default 0,
  source text not null default 'pos',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, business_date, source, register_code, group_code)
);

create index if not exists idx_pos_group_branch_date on pos_register_daily_sales_groups(branch_id, business_date);

create table if not exists cash_reconciliations (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  business_date date not null,
  expected_sales_total numeric(14,2) not null default 0,
  status text not null default 'draft',
  created_by_user_id uuid not null references app_users(id),
  approved_by_user_id uuid references app_users(id),
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, business_date)
);

create table if not exists cash_reconciliation_payment_lines (
  id uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references cash_reconciliations(id) on delete cascade,
  payment_type_id uuid not null references payment_types(id),
  amount numeric(14,2) not null,
  created_at timestamptz not null default now(),
  unique (reconciliation_id, payment_type_id)
);

create table if not exists cash_reconciliation_expense_lines (
  id uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references cash_reconciliations(id) on delete cascade,
  expense_type_id uuid not null references expense_types(id),
  amount numeric(14,2) not null,
  created_at timestamptz not null default now(),
  unique (reconciliation_id, expense_type_id)
);

create table if not exists cash_reconciliation_attachments (
  id uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references cash_reconciliations(id) on delete cascade,
  kind text not null,
  file_name text not null,
  mime_type text not null,
  size_bytes bigint not null,
  storage_key text,
  uploaded_by_user_id uuid references app_users(id),
  created_at timestamptz not null default now()
);

create table if not exists pos_end_of_day_reports (
  id uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references cash_reconciliations(id) on delete cascade,
  branch_id uuid not null references branches(id),
  business_date date not null,
  report_date date not null,
  merchant_title text,
  workplace_no text,
  terminal_no text,
  card_total numeric(14,2) not null default 0,
  fast_total numeric(14,2) not null default 0,
  raw_text text,
  created_by_user_id uuid references app_users(id),
  created_at timestamptz not null default now()
);

alter table if exists pos_end_of_day_reports
  add column if not exists fast_total numeric(14,2) not null default 0;

create index if not exists idx_eod_recon on pos_end_of_day_reports(reconciliation_id);

create table if not exists cash_reconciliation_audit (
  id uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references cash_reconciliations(id) on delete cascade,
  actor_user_id uuid references app_users(id),
  action text not null,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists idx_recon_branch_date on cash_reconciliations(branch_id, business_date);
create index if not exists idx_recon_status on cash_reconciliations(status);
create index if not exists idx_daily_sales_branch_date on daily_sales(branch_id, business_date);

create table if not exists inv_products (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  unit text not null default 'adet',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists inv_warehouses (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  code text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, code)
);

create table if not exists inv_stock_transactions (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  warehouse_id uuid not null references inv_warehouses(id),
  business_date date not null,
  kind text not null,
  reference_no text,
  notes text,
  created_by_user_id uuid not null references app_users(id),
  created_at timestamptz not null default now()
);

create table if not exists inv_stock_transaction_lines (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references inv_stock_transactions(id) on delete cascade,
  product_id uuid not null references inv_products(id),
  quantity numeric(14,3) not null,
  unit_cost numeric(14,4) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_inv_products_active on inv_products(is_active);
create index if not exists idx_inv_wh_branch on inv_warehouses(branch_id, is_active);
create index if not exists idx_inv_tx_branch_date on inv_stock_transactions(branch_id, business_date);
create index if not exists idx_inv_tx_wh_date on inv_stock_transactions(warehouse_id, business_date);
create index if not exists idx_inv_tx_line_prod on inv_stock_transaction_lines(product_id);

create table if not exists inv_stock_counts (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  warehouse_id uuid not null references inv_warehouses(id),
  business_date date not null,
  status text not null default 'draft',
  created_by_user_id uuid not null references app_users(id),
  approved_by_user_id uuid references app_users(id),
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (warehouse_id, business_date)
);

create table if not exists inv_stock_count_lines (
  id uuid primary key default gen_random_uuid(),
  count_id uuid not null references inv_stock_counts(id) on delete cascade,
  product_id uuid not null references inv_products(id),
  counted_qty numeric(14,3) not null,
  onhand_qty numeric(14,3) not null default 0,
  diff_qty numeric(14,3) not null default 0,
  created_at timestamptz not null default now(),
  unique (count_id, product_id)
);

create index if not exists idx_inv_count_wh_date on inv_stock_counts(warehouse_id, business_date);
create index if not exists idx_inv_count_status on inv_stock_counts(status);
create index if not exists idx_inv_count_lines_product on inv_stock_count_lines(product_id);

create table if not exists inv_recipes (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references inv_products(id),
  code text,
  name text not null,
  description text,
  yield_qty numeric(14,3) not null default 1,
  yield_unit text not null default 'adet',
  gim_oran numeric(6,2),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id)
);

create table if not exists inv_recipe_lines (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references inv_recipes(id) on delete cascade,
  ingredient_product_id uuid not null references inv_products(id),
  quantity numeric(14,3) not null,
  unit text,
  waste_rate numeric(18,5),
  created_at timestamptz not null default now(),
  unique (recipe_id, ingredient_product_id)
);

create index if not exists idx_inv_recipe_active on inv_recipes(is_active);
create index if not exists idx_inv_recipe_lines_ingredient on inv_recipe_lines(ingredient_product_id);

alter table if exists inv_recipes
  add column if not exists code text;
alter table if exists inv_recipes
  add column if not exists description text;
alter table if exists inv_recipes
  add column if not exists gim_oran numeric(6,2);

alter table if exists inv_recipe_lines
  add column if not exists unit text;
alter table if exists inv_recipe_lines
  add column if not exists waste_rate numeric(18,5);

create table if not exists crm_firms (
  id uuid primary key default gen_random_uuid(),
  firm_name text not null,
  trade_name text,
  integration_code text,
  firm_type text,
  is_current boolean not null default true,
  customer_group text,
  email text,
  price_no text,
  wholesale_price_no text,
  invoice_company text,
  general_discount numeric(14,4),
  payment_method text,
  tax_office text,
  tax_no text,
  is_einvoice boolean not null default false,
  cargo_code text,
  purchase_price_no text,
  payment_vkn text,
  iban text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_crm_firms_active on crm_firms(is_active);
create index if not exists idx_crm_firms_name on crm_firms(lower(firm_name));
create index if not exists idx_crm_firms_tax on crm_firms(tax_no);

create table if not exists income_centers (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_income_centers_active on income_centers(is_active);
create index if not exists idx_income_centers_name on income_centers(lower(name));

create table if not exists cash_registers (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_cash_registers_active on cash_registers(is_active);
create index if not exists idx_cash_registers_name on cash_registers(lower(name));

create table if not exists branch_cash_registers (
  branch_id uuid not null references branches(id) on delete cascade,
  cash_register_id uuid not null references cash_registers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (branch_id, cash_register_id)
);

create index if not exists idx_branch_cash_registers_branch on branch_cash_registers(branch_id);

create table if not exists unit_sets (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_unit_sets_active on unit_sets(is_active);
create index if not exists idx_unit_sets_name on unit_sets(lower(name));

create table if not exists account_periods (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  start_date date not null,
  end_date date not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_account_periods_active on account_periods(is_active);

create table if not exists workstations (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_workstations_active on workstations(is_active);
create index if not exists idx_workstations_name on workstations(lower(name));

create table if not exists branch_waste_warehouse (
  branch_id uuid primary key references branches(id) on delete cascade,
  warehouse_id uuid references inv_warehouses(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists inv_invoices (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  invoice_no text not null,
  invoice_date date not null,
  vendor_name text,
  notes text,
  created_by_user_id uuid references app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, invoice_no)
);

create index if not exists idx_inv_invoices_branch_date on inv_invoices(branch_id, invoice_date);

create table if not exists inv_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references inv_invoices(id) on delete cascade,
  description text not null,
  quantity numeric(14,4) not null default 0,
  unit_price numeric(14,4) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_inv_invoice_lines_invoice on inv_invoice_lines(invoice_id);

alter table if exists inv_invoices
  add column if not exists payment_type_id uuid references payment_types(id);
alter table if exists inv_invoices
  add column if not exists income_center_id uuid references income_centers(id);
alter table if exists inv_invoices
  add column if not exists discount_rate numeric(9,4);
alter table if exists inv_invoices
  add column if not exists discount_amount numeric(14,4);
alter table if exists inv_invoices
  add column if not exists meal_voucher_discount numeric(14,4);
alter table if exists inv_invoices
  add column if not exists payment_date date;

alter table if exists inv_invoice_lines
  add column if not exists product_id uuid references inv_products(id);
alter table if exists inv_invoice_lines
  add column if not exists unit text;

create index if not exists idx_inv_invoices_payment_type on inv_invoices(payment_type_id);
create index if not exists idx_inv_invoices_income_center on inv_invoices(income_center_id);
create index if not exists idx_inv_invoice_lines_product on inv_invoice_lines(product_id);

create table if not exists min_max_definitions (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id) on delete cascade,
  product_name text not null,
  min_qty numeric(14,4) not null default 0,
  max_qty numeric(14,4) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_min_max_branch on min_max_definitions(branch_id);
create index if not exists idx_min_max_product on min_max_definitions(lower(product_name));

create table if not exists unproduced_products (
  id uuid primary key default gen_random_uuid(),
  product_name text not null unique,
  is_blocked boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_unproduced_products_blocked on unproduced_products(is_blocked);
create index if not exists idx_unproduced_products_name on unproduced_products(lower(product_name));

create table if not exists user_menu_permissions (
  user_id uuid not null references app_users(id) on delete cascade,
  legacy_ref text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, legacy_ref)
);

create index if not exists idx_user_menu_permissions_user on user_menu_permissions(user_id);
