# PostgreSQL Setup

Bu loyiha endi `SQLite` yoki `PostgreSQL` bilan ishlay oladi.

## Local Mac setup

1. Local Postgres tayyorlash:

```bash
chmod +x tools/setup_local_postgres.sh
POSTGRES_PASSWORD=pqc_chat_app_dev_password ./tools/setup_local_postgres.sh
```

2. Django'ni Postgres bilan ishga tushirish:

```bash
export DB_BACKEND=postgres
export POSTGRES_DB=pqc_chat_app
export POSTGRES_USER=pqc_chat_app
export POSTGRES_PASSWORD=pqc_chat_app_dev_password
export POSTGRES_HOST=127.0.0.1
export POSTGRES_PORT=5432

backend/.venv/bin/python backend/manage.py migrate
backend/.venv/bin/python backend/manage.py runserver 0.0.0.0:8000
```

## Remote server setup

SSH access bo'lsa, serverda quyidagi bazaviy qadamlar ishlatiladi:

```bash
sudo apt-get update
sudo apt-get install -y postgresql postgresql-contrib
sudo -u postgres psql -c "CREATE ROLE pqc_chat_app WITH LOGIN PASSWORD 'CHANGE_ME';"
sudo -u postgres createdb -O pqc_chat_app pqc_chat_app
```

Django env:

```bash
export DB_BACKEND=postgres
export POSTGRES_DB=pqc_chat_app
export POSTGRES_USER=pqc_chat_app
export POSTGRES_PASSWORD=CHANGE_ME
export POSTGRES_HOST=127.0.0.1
export POSTGRES_PORT=5432
```

Keyin:

```bash
backend/.venv/bin/python backend/manage.py migrate
```

## Existing SQLite data ko'chirish

Agar eski SQLite ma'lumotini Postgres'ga olib o'tish kerak bo'lsa:

```bash
backend/.venv/bin/python backend/manage.py dumpdata \
  --exclude contenttypes \
  --exclude auth.permission \
  --indent 2 > shared/sqlite_export.json
```

Postgres env bilan migrate qilgandan keyin:

```bash
backend/.venv/bin/python backend/manage.py loaddata shared/sqlite_export.json
```

## Priority note

`200` concurrent write stress-testda asosiy bottleneck `SQLite` bo'ldi. `PostgreSQL`ga o'tish shu yadro uchun keyingi to'g'ri production qadami.
