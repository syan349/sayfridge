"""Reproduce SayFridge's isolated 5 RPS baseline without Git or hosted DB writes.

Requires backend/requirements.txt and backend/.env.e2e (loopback disposable DB).
Run with --root <repository> --output <new evidence directory>. Optional real
model samples use backend/.env; credentials and response bodies are never saved.
"""
from __future__ import annotations
import argparse
import asyncio
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import secrets
import socket
import subprocess
import sys
import threading
import time
from uuid import uuid4
from zoneinfo import ZoneInfo

import httpx
import psycopg
from psycopg import sql
from dotenv import dotenv_values


def stamp():
    return datetime.now(timezone.utc).isoformat()


def percentile(values, p):
    values = sorted(values)
    return round(values[max(0, math.ceil(len(values) * p) - 1)], 3) if values else None


def stats(rows):
    latencies = [r['elapsed_ms'] for r in rows if r.get('started', True)]
    failures = sum(not r['ok'] for r in rows)
    return {'requests': len(rows), 'failures': failures,
            'error_rate': failures / len(rows) if rows else None,
            'p50_ms': percentile(latencies, .50), 'p95_ms': percentile(latencies, .95),
            'p99_ms': percentile(latencies, .99), 'max_ms': max(latencies, default=None)}


def summarise(rows):
    groups = defaultdict(list)
    for row in rows:
        groups[row['scenario']].append(row)
    return {key: stats(value) for key, value in sorted(groups.items())}


def source_manifest(root):
    files = sorted(p for p in (root / 'backend').rglob('*') if p.is_file()
                   and p.suffix in {'.py', '.ini', '.txt', '.toml'}
                   and '__pycache__' not in p.parts and not p.name.startswith('.')
                   and '.venv' not in p.parts)
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


def revision(root):
    git = root / '.git'
    head = (git / 'HEAD').read_text().strip()
    if not head.startswith('ref: '):
        return head, 'detached'
    ref = head[5:]
    path = git / ref
    if path.exists():
        return path.read_text().strip(), ref
    for line in (git / 'packed-refs').read_text().splitlines():
        if line.endswith(' ' + ref):
            return line.split()[0], ref
    raise RuntimeError('Cannot read code revision')


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def save(path, data):
    path.write_text(json.dumps(data, indent=2, default=str) + '\n')


def seed(conn, root, as_of):
    sys.path.insert(0, str(root / 'backend'))
    from app.core.security import hash_password
    password = secrets.token_urlsafe(24)
    hashed = hash_password(password)
    users = [uuid4() for _ in range(100)]
    spaces = [uuid4() for _ in users]
    definitions = [uuid4() for _ in range(100)]
    categories = conn.execute('SELECT id FROM item_category ORDER BY sort_order,id').fetchall()
    if len(categories) != 25:
        raise RuntimeError('Expected 25 initialized public categories')
    with conn.cursor().copy('COPY "user" (id,email,password_hash) FROM STDIN') as copy:
        for i, uid in enumerate(users):
            copy.write_row((uid, f'perf-{i:03d}@example.com', hashed))
    with conn.cursor().copy('COPY storage_space (id,user_id,name,type,is_default) FROM STDIN') as copy:
        for uid, sid in zip(users, spaces):
            copy.write_row((sid, uid, 'Performance Fridge', 'FRIDGE', True))
    with conn.cursor().copy('COPY item_definition (id,name,normalized_name,category_id) FROM STDIN') as copy:
        for i, did in enumerate(definitions):
            name = f'Performance rice {i:03d}'
            copy.write_row((did, name, name.lower(), categories[i % 25][0]))
    distribution = [20000] + [303] * 98 + [306]
    items, owner_items = [], [[] for _ in users]
    now = datetime.now(timezone.utc)
    with conn.cursor().copy('COPY inventory_item (id,storage_space_id,item_definition_id,initial_amount,initial_unit,confirmed_current_amount,confirmed_current_unit,confirmed_at,expiry_date,version,created_at,updated_at) FROM STDIN') as copy:
        n = 0
        for user, count in enumerate(distribution):
            for j in range(count):
                iid = uuid4()
                expiry = as_of + timedelta(days=(j % 30) - 10)
                copy.write_row((iid, spaces[user], definitions[n % 100], Decimal('1000'), 'kg', Decimal('1000'), 'kg', now, expiry, 11, now, now))
                items.append(iid)
                owner_items[user].append(str(iid))
                n += 1
    with conn.cursor().copy('COPY inventory_operation (id,inventory_item_id,operation_type,affects_state,input_method,quantity_kind,quantity_value,quantity_unit,calculation_method,applied_change_amount,applied_change_unit,status,idempotency_key,created_at,updated_at) FROM STDIN') as copy:
        for n, iid in enumerate(items):
            for j in range(10):
                at = now - timedelta(minutes=10 - j)
                copy.write_row((uuid4(), iid, 'ADD' if j % 2 == 0 else 'CONSUME', 'CONFIRMED', 'MANUAL', 'AMOUNT', '1', 'kg', 'EXACT', Decimal('1'), 'kg', 'SUCCESS', f'perf-seed-{n}-{j}', at, at))
    conn.commit()
    conn.execute('ANALYZE')
    conn.commit()
    counts = conn.execute('SELECT (SELECT count(*) FROM "user"),(SELECT count(*) FROM inventory_item),(SELECT count(*) FROM inventory_operation)').fetchone()
    assert counts == (100, 50000, 500000), counts
    return {'users': list(map(str, users)), 'spaces': list(map(str, spaces)),
            'definitions': list(map(str, definitions)), 'category': str(categories[0][0]),
            'items': owner_items, 'distribution': distribution, 'password': password,
            'counts': {'users': counts[0], 'inventory_batches': counts[1], 'quantity_operations': counts[2]}}


async def measured(client, rows, phase, scenario, method, path, *, headers=None,
                   body=None, expected=200, check=None, user=None, scheduled=None):
    start = time.perf_counter()
    row = {'phase': phase, 'scenario': scenario, 'method': method,
           'user_index': user, 'scheduled_offset_s': scheduled, 'started': True,
           'utc': stamp()}
    try:
        response = await client.request(method, path, headers=headers, json=body)
        row['elapsed_ms'] = round((time.perf_counter() - start) * 1000, 3)
        row['status'] = response.status_code
        row['bytes'] = len(response.content)
        payload = response.json() if response.content else None
        row['ok'] = response.status_code == expected
        if row['ok'] and check:
            row['ok'] = bool(check(payload))
            if not row['ok']:
                row['failure'] = 'business_assertion'
        elif not row['ok']:
            detail = payload.get('detail') if isinstance(payload, dict) else None
            row['failure'] = detail.get('code', 'unexpected_http_status') if isinstance(detail, dict) else 'unexpected_http_status'
    except Exception as exc:
        row.update(elapsed_ms=round((time.perf_counter() - start) * 1000, 3),
                   status=None, ok=False, failure=type(exc).__name__)
        payload = None
    rows.append(row)
    return payload, row


async def login_users(client, data, rows):
    headers, refresh = [], []
    for i in range(10):
        payload, row = await measured(client, rows, 'authentication', 'login', 'POST', '/auth/login',
            body={'email': f'perf-{i:03d}@example.com', 'password': data['password']},
            check=lambda x: bool(x.get('access_token') and x.get('refresh_token')), user=i)
        if not row['ok']:
            raise RuntimeError('Isolated login failed')
        headers.append({'Authorization': 'Bearer ' + payload['access_token']})
        refresh.append(payload['refresh_token'])
    return headers, refresh


async def baseline(client, data, headers, duration, rate, phase, all_rows):
    start = time.perf_counter()
    rows, tasks = [], set()
    busy = [False] * 10
    active = maximum = dropped = 0
    scheduled = round(duration * rate)

    async def one(n, user):
        nonlocal active, maximum
        dispatch_lag_ms = max(0, (time.perf_counter() - start - n / rate) * 1000)
        busy[user] = True
        active += 1
        maximum = max(maximum, active)
        h = headers[user]
        item = data['items'][user][0]
        total = data['distribution'][user]
        slot = n % 10
        path, method, body, expect = '/inventory-items', 'GET', None, 200
        if slot == 0:
            name = 'inventory_list'
            path += '?page_size=20'
            check = lambda x: x['total'] >= total and len(x['items']) == 20 and all(v['storage_space_id'] == data['spaces'][user] for v in x['items'])
        elif slot == 1:
            name = 'inventory_search'
            path += '?q=Performance%20rice&page_size=20&page=2'
            check = lambda x: x['total'] >= total and len(x['items']) == 20 and all('Performance rice' in v['item_definition_name'] for v in x['items'])
        elif slot == 2:
            name = 'inventory_space_filter'
            path += '?storage_space_id=' + data['spaces'][user] + '&page_size=20'
            check = lambda x: x['total'] >= total and all(v['storage_space_id'] == data['spaces'][user] for v in x['items'])
        elif slot == 3:
            name = 'inventory_category_filter'
            path += '?category_id=' + data['category'] + '&page_size=20'
            check = lambda x: x['total'] > 0 and bool(x['items']) and all(v['category_id'] == data['category'] for v in x['items'])
        elif slot == 4:
            name = 'inventory_detail'
            path += '/' + item
            check = lambda x: x['id'] == item and x['storage_space_id'] == data['spaces'][user]
        elif slot == 5:
            name = 'operation_history_page'
            path = '/inventory-operations?page_size=20'
            check = lambda x: x['total'] >= total * 10 and len(x['items']) == 20
        elif slot in (6, 7):
            name = 'expiry_summary' if slot == 6 else 'expiry_bucket'
            path += '/expiry-summary?as_of=' + data['as_of'] + '&page_size=20'
            if slot == 7:
                path += '&bucket=overdue'
            check = lambda x: x['total'] > 0 and bool(x['items']) and all(v['storage_space_id'] == data['spaces'][user] for v in x['items']) and (slot == 6 or all(v['bucket'] == 'overdue' for v in x['items']))
        else:
            mode = 'CONSUME' if slot == 8 else ('ADD', 'RECONCILE', 'CREATE')[((n // 10) // 10) % 3]
            method, expect = 'POST', 201
            if mode == 'CREATE':
                name = 'stock_create'
                body = {'storage_space_id': data['spaces'][user], 'item_definition_id': data['definitions'][user], 'amount': '1000', 'unit': 'kg', 'expiry_date': data['as_of']}
                check = lambda x: x['version'] == 1 and x['storage_space_id'] == data['spaces'][user] and Decimal(x['display_amount']) == 1000
            else:
                name = 'quantity_' + mode.lower()
                path += '/' + item + '/operations'
                h = {**h, 'Idempotency-Key': str(uuid4())}
                version = data['versions'][user]
                balance = data['balances'][user]
                expected_balance = Decimal('1000') if mode == 'RECONCILE' else balance + (Decimal('0.001') if mode == 'ADD' else -Decimal('0.001'))
                body = {'expected_version': version, 'operation_type': mode, 'quantity_kind': 'AMOUNT', 'quantity_value': '1000' if mode == 'RECONCILE' else '0.001', 'quantity_unit': 'kg'}
                check = lambda x: x['inventory']['id'] == item and x['inventory']['version'] == version + 1 and Decimal(x['inventory']['confirmed_current_amount']) == expected_balance and x['operation']['status'] == 'SUCCESS' and not x['replayed']
        try:
            payload, row = await measured(client, rows, phase, name, method, path, headers=h, body=body, expected=expect, check=check, user=user, scheduled=n / rate)
            row['dispatch_lag_ms'] = round(dispatch_lag_ms, 3)
            if row['ok'] and slot > 7 and mode != 'CREATE':
                data['versions'][user] = payload['inventory']['version']
                data['balances'][user] = Decimal(payload['inventory']['confirmed_current_amount'])
        finally:
            busy[user] = False
            active -= 1

    for n in range(scheduled):
        await asyncio.sleep(max(0, start + n / rate - time.perf_counter()))
        user = ((n // 10) + n % 10) % 10
        if busy[user]:
            dropped += 1
            rows.append({'phase': phase, 'scenario': 'dropped_arrival', 'started': False,
                         'elapsed_ms': 0, 'ok': False, 'user_index': user, 'scheduled_offset_s': n / rate})
            continue
        task = asyncio.create_task(one(n, user))
        tasks.add(task)
        task.add_done_callback(tasks.discard)
    if tasks:
        await asyncio.gather(*tasks)
    await asyncio.sleep(max(0, start + duration - time.perf_counter()))
    elapsed = time.perf_counter() - start
    all_rows.extend(rows)
    read = [r for r in rows if r.get('method') == 'GET']
    write = [r for r in rows if r.get('method') == 'POST']
    result = {'duration_s': round(elapsed, 3), 'target_duration_s': duration,
              'target_rps': rate, 'scheduled': scheduled, 'sent': scheduled - dropped,
              'dropped_arrivals': dropped, 'actual_rps': round((scheduled-dropped) / elapsed, 4),
              'maximum_in_flight': maximum, 'active_identities': 10,
              'max_schedule_lag_ms': max((r.get('dispatch_lag_ms', 0) for r in rows), default=0),
              'overall': stats(rows), 'reads': stats(read), 'writes': stats(write),
              'scenarios': summarise(rows)}
    result['acceptance'] = {'read_p95_le_500ms': bool(read) and result['reads']['p95_ms'] <= 500,
        'write_p95_le_1000ms': bool(write) and result['writes']['p95_ms'] <= 1000,
        'unexpected_errors_lt_1pct': bool(rows) and result['overall']['error_rate'] < .01,
        'no_dropped_arrivals': dropped == 0, 'all_requests_business_valid': all(r['ok'] for r in rows)}
    result['pass'] = all(result['acceptance'].values())
    print(phase, 'completed:', json.dumps({'read_p95_ms': result['reads']['p95_ms'], 'write_p95_ms': result['writes']['p95_ms'], 'failures': result['overall']['failures'], 'dropped': dropped}), flush=True)
    return result


async def contention(client, data, headers, rows):
    start = len(rows)
    user = 0
    item = data['items'][user][1]
    base = '/inventory-items/' + item
    payload = (await client.get(base, headers=headers[user])).json()
    version = payload['version']
    responses = await asyncio.gather(*[measured(client, rows, 'contention', 'same_item_competing_edits', 'PATCH', base,
        headers=headers[user], body={'expected_version': version, 'notes': 'Contention ' + str(i)}, expected=200, user=user) for i in range(2)])
    statuses = sorted(r['status'] for _, r in responses)
    for body, row in responses:
        row['ok'] = row['status'] == 200 or (row['status'] == 409 and body.get('detail', {}).get('code') == 'VERSION_CONFLICT')
    same_item_ok = statuses == [200, 409] and (await client.get(base, headers=headers[user])).json()['version'] == version + 1
    responses = await asyncio.gather(*[measured(client, rows, 'contention', 'same_space_different_items', 'PATCH', '/inventory-items/' + data['items'][user][j],
        headers=headers[user], body={'expected_version': 11, 'notes': 'Independent item'}, expected=200, user=user) for j in (2, 3)])
    return {'same_item_statuses': statuses, 'same_item_exactly_one_commit': same_item_ok,
            'same_space_two_items_both_committed': all(r['ok'] for _, r in responses),
            'timings': summarise(rows[start:])}


async def agent_samples(client, data, headers, n, output):
    rows = []
    messages = [('clarification', 'I consumed some rice today. Please ask me which batch and quantity before changing stock.'),
                ('inventory_read', 'How many inventory batches do I currently have? Please use the inventory tool; do not change any stock.'),
                ('consume', 'I consumed 1 kg from inventory batch ' + data['items'][1][0] + ' in Performance Fridge today. Use that exact batch ID, without changing any other batch.'),
                ('stock_entry', 'I bought 2 kg of bananas today and put them in Performance Fridge. The expiry date is 2026-10-20.')]
    # Serial real workflow calls on ordinary user 1, each with a fresh conversation.
    for i in range(n):
        scenario, message = messages[i % len(messages)]
        started, first_content, done = time.perf_counter(), None, None
        events = Counter()
        row = {'sample': i + 1, 'scenario': scenario, 'utc': stamp()}
        try:
            async with client.stream('POST', '/agent/chat', headers=headers[1],
                json={'message': message, 'as_of': data['as_of'], 'conversation_id': str(uuid4()), 'request_id': str(uuid4())}, timeout=120) as response:
                row['http_status'] = response.status_code
                async for line in response.aiter_lines():
                    if not line.startswith('data:'):
                        continue
                    event = json.loads(line[5:])
                    typ = event.get('type', '')
                    events[typ] += 1
                    if typ in {'text_delta', 'action_required', 'operation_preview', 'operation_result'} and first_content is None:
                        first_content = time.perf_counter() - started
                    if typ == 'done':
                        done = event
                    if typ == 'error':
                        row['error_code'] = event.get('code', 'unknown')
            states = (done or {}).get('data', {}).get('items', [])
            row['item_statuses'] = [x.get('status') for x in states]
            row['business_successes'] = sum(x.get('status') == 'SUCCEEDED' for x in states)
            row['http_stream_ok'] = row.get('http_status') == 200 and done is not None and not events['error']
            row['workflow_ok'] = row['http_stream_ok'] and (any(x.get('status') == 'NEEDS_INPUT' for x in states) if scenario == 'clarification' else (not states if scenario == 'inventory_read' else bool(states) and all(x.get('status') in {'SUCCEEDED', 'NEEDS_CONFIRMATION'} for x in states)))
            row['outcome'] = (done or {}).get('status')
            # Verify business persistence when the stream says a write succeeded.
            persisted = True
            for item in states:
                inventory = (item.get('result') or {}).get('inventory')
                if item.get('status') == 'SUCCEEDED' and inventory:
                    check_response = await client.get('/inventory-items/' + inventory['id'], headers=headers[1])
                    saved = check_response.json()
                    persisted &= check_response.status_code == 200 and saved['version'] == inventory['version'] and saved['confirmed_current_amount'] == inventory['confirmed_current_amount']
            row['persistence_verified'] = persisted if row['business_successes'] else None
            row['workflow_ok'] &= persisted
        except Exception as exc:
            row.update(http_stream_ok=False, workflow_ok=False, error_code=type(exc).__name__)
        row.update(first_content_ms=round(first_content * 1000, 3) if first_content is not None else None,
                   total_ms=round((time.perf_counter() - started) * 1000, 3), events=dict(events))
        rows.append(row)
        save(output / 'agent-samples.json', rows)
        print('Agent sample', i+1, scenario, 'stream', row['http_stream_ok'], 'workflow', row['workflow_ok'], 'total_ms', row['total_ms'], flush=True)
    return {'samples': rows, 'count': len(rows), 'http_stream_failures': sum(not r['http_stream_ok'] for r in rows),
            'workflow_failures': sum(not r['workflow_ok'] for r in rows),
            'median_first_content_ms': percentile([r['first_content_ms'] for r in rows if r['first_content_ms'] is not None], .5),
            'median_total_ms': percentile([r['total_ms'] for r in rows], .5),
            'max_total_ms': max((r['total_ms'] for r in rows), default=None)}


def monitor(dsn, name, stop, rows):
    try:
        with psycopg.connect(dsn, autocommit=True, application_name='performance-observer') as connection:
            while not stop.is_set():
                row = connection.execute("SELECT count(*), count(*) FILTER (WHERE state='active'), count(*) FILTER (WHERE wait_event_type='Lock') FROM pg_stat_activity WHERE application_name=%s", (name,)).fetchone()
                rows.append({'utc': stamp(), 'connections': row[0], 'active': row[1], 'lock_waiters': row[2]})
                stop.wait(2)
    except Exception as exc:
        rows.append({'error_type': type(exc).__name__})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--warmup', type=int, default=120)
    parser.add_argument('--duration', type=int, default=600)
    parser.add_argument('--rps', type=float, default=5)
    parser.add_argument('--agent-samples', type=int, default=10)
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(root / 'backend'))
    from scripts.run_e2e import database_target
    database = database_target(os.environ.get('E2E_DATABASE_URL') or dotenv_values(root / 'backend/.env.e2e').get('E2E_DATABASE_URL'))
    sha, branch = revision(root)
    manifest = source_manifest(root)
    suffix = uuid4().hex
    schema, agent_schema = 'perf_' + suffix, 'perf_' + suffix + '_agent'
    app_name = 'perf_' + suffix
    scoped = database.update_query_dict({'options': '-csearch_path=' + schema, 'application_name': app_name})
    dsn = scoped.render_as_string(hide_password=False).replace('postgresql+psycopg://', 'postgresql://', 1)
    raw_dsn = database.render_as_string(hide_password=False).replace('postgresql+psycopg://', 'postgresql://', 1)
    model = dotenv_values(root / 'backend/.env')
    env = os.environ.copy()
    for key, value in model.items():
        if key.startswith('AGENT_') and value is not None:
            env[key] = value
    env.update(DATABASE_URL=scoped.render_as_string(hide_password=False), DATABASE_URL_DIRECT=scoped.render_as_string(hide_password=False),
               AGENT_DATABASE_URL=scoped.render_as_string(hide_password=False), AGENT_DATABASE_SCHEMA=agent_schema,
               JWT_SECRET_KEY=secrets.token_urlsafe(48), CORS_ORIGINS='[]', APP_COMMIT_SHA=sha, APP_VERSION='0.1.0-performance')
    as_of = datetime.now(ZoneInfo('Pacific/Auckland')).date()
    result = {'started_utc': stamp(), 'started_nz': datetime.now(ZoneInfo('Pacific/Auckland')).isoformat(),
        'commit': sha, 'git_ref_at_start': branch, 'backend_source_manifest': manifest,
        'harness_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'environment': {'os': platform.platform(), 'machine': platform.machine(), 'python': platform.python_version(),
            'logical_cpus': os.cpu_count(), 'backend_workers': 1, 'reload': False, 'client_location': 'same Mac as Backend; PostgreSQL in Docker',
            'transport': 'loopback HTTP; no TLS or WAN', 'runtime_business_pool': {'pool_size': 5, 'max_overflow': 10, 'pool_pre_ping': True},
            'agent_pool': {'min': env.get('AGENT_DB_POOL_MIN_SIZE', '1'), 'max': env.get('AGENT_DB_POOL_MAX_SIZE', '4')},
            'versions': {p: importlib.metadata.version(p) for p in ['fastapi','uvicorn','httpx','psycopg','SQLAlchemy','langgraph','langchain-openai']}},
        'configuration': {'warmup_seconds': args.warmup, 'baseline_seconds': args.duration, 'rps': args.rps, 'read_write_mix': '80/20', 'users': 10,
            'arrival_model': 'fixed scheduled arrivals, max one outstanding request per user; record busy-user drops', 'http_timeout_seconds': 10,
            'percentiles': 'nearest rank; full response body received, before JSON assertions', 'random_user_distribution': False},
        'schema': schema, 'agent_schema': agent_schema, 'as_of': str(as_of)}
    for key in ['hw.memsize','hw.physicalcpu','machdep.cpu.brand_string']:
        try:
            result['environment'][key] = subprocess.check_output(['sysctl', '-n', key], text=True).strip()
        except Exception:
            pass
    process = None
    rows, observations = [], []
    observer_stop = threading.Event()
    observer = None
    started = time.perf_counter()
    try:
        with (output / 'initialize.log').open('w') as log:
            subprocess.run([sys.executable, 'scripts/initialize_database.py', '--business-schema', schema], cwd=root / 'backend', env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
        with psycopg.connect(dsn) as conn:
            result['environment']['postgresql'] = conn.execute('SHOW server_version').fetchone()[0]
            data = seed(conn, root, as_of)
            result['seed_counts'] = data['counts']
            result['seed_user_distribution'] = data['distribution']
        data.update(as_of=str(as_of), versions=[11] * 10, balances=[Decimal('1000')] * 10)
        result['setup_seconds'] = round(time.perf_counter() - started, 3)
        print('Seed ready:', result['seed_counts'], 'setup_s', result['setup_seconds'], flush=True)
        port = free_port()
        api = f'http://127.0.0.1:{port}'
        log = (output / 'backend.log').open('w')
        process = subprocess.Popen([sys.executable, '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', str(port), '--no-access-log'], cwd=root / 'backend', env=env, stdout=log, stderr=subprocess.STDOUT)
        for _ in range(300):
            if process.poll() is not None:
                raise RuntimeError('Isolated backend exited')
            try:
                if httpx.get(api + '/health', timeout=1).status_code == 200:
                    break
            except httpx.HTTPError:
                pass
            time.sleep(.2)
        else:
            raise RuntimeError('Backend readiness timed out')
        observer = threading.Thread(target=monitor, args=(raw_dsn, app_name, observer_stop, observations), daemon=True)
        observer.start()

        async def run():
            async with httpx.AsyncClient(base_url=api + '/api/v1', timeout=10, limits=httpx.Limits(max_connections=10, max_keepalive_connections=10), trust_env=False) as client:
                h, refresh = await login_users(client, data, rows)
                # A small complete cycle verifies request shapes before the timed run.
                result['smoke'] = await baseline(client, data, h, 2, 5, 'smoke', rows)
                if not result['smoke']['acceptance']['all_requests_business_valid']:
                    raise RuntimeError('Performance harness smoke assertions failed')
                print('Starting two-minute warm-up then ten-minute baseline', flush=True)
                result['warmup'] = await baseline(client, data, h, args.warmup, args.rps, 'warmup', rows)
                result['baseline'] = await baseline(client, data, h, args.duration, args.rps, 'baseline', rows)
                save(output / 'results.json', result)
                # Check exact final balances/versions in PostgreSQL before contention/AI writes.
                with psycopg.connect(dsn) as conn:
                    verified = []
                    for i in range(10):
                        actual = conn.execute('SELECT version,confirmed_current_amount FROM inventory_item WHERE id=%s', (data['items'][i][0],)).fetchone()
                        verified.append(actual == (data['versions'][i], data['balances'][i]))
                    result['persistence_check'] = {'items': 10, 'all_exact_versions_and_balances_match': all(verified)}
                result['contention'] = await contention(client, data, h, rows)
                if args.agent_samples and all(env.get(k) for k in ['AGENT_MODEL','AGENT_API_BASE','AGENT_API_KEY']):
                    # Renew before the slow serial model samples; exclude this from baseline.
                    for i in range(10):
                        payload, row = await measured(client, rows, 'authentication', 'refresh', 'POST', '/auth/refresh', body={'refresh_token': refresh[i]}, check=lambda x: bool(x.get('access_token')), user=i)
                        if not row['ok']:
                            raise RuntimeError('Isolated refresh failed')
                        h[i] = {'Authorization': 'Bearer ' + payload['access_token']}
                        refresh[i] = payload['refresh_token']
                    result['agent_model'] = env['AGENT_MODEL']
                    result['agent'] = await agent_samples(client, data, h, args.agent_samples, output)
                else:
                    result['agent'] = {'status': 'not_run', 'reason': 'No configured model or zero requested samples'}
                for token in refresh:
                    _, row = await measured(client, rows, 'cleanup', 'logout', 'POST', '/auth/logout', body={'refresh_token': token}, expected=204)
                    if not row['ok']:
                        result['logout_failed'] = True
        asyncio.run(run())
        result['authentication'] = summarise([r for r in rows if r['phase'] == 'authentication'])
        result['completed'] = True
    except Exception as exc:
        result.update(completed=False, error_type=type(exc).__name__)
        print('Performance run stopped:', type(exc).__name__, flush=True)
    finally:
        observer_stop.set()
        if observer:
            observer.join(timeout=10)
        if process:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            log.close()
        try:
            with psycopg.connect(raw_dsn, autocommit=True) as conn:
                for name in [agent_schema, schema]:
                    conn.execute(sql.SQL('DROP SCHEMA IF EXISTS {} CASCADE').format(sql.Identifier(name)))
                present = conn.execute('SELECT count(*) FROM pg_namespace WHERE nspname IN (%s,%s)', (schema, agent_schema)).fetchone()[0]
            result['cleanup'] = {'schemas_remaining': present, 'pass': present == 0}
        except Exception as exc:
            result['cleanup'] = {'pass': False, 'error_type': type(exc).__name__}
        result['source_unchanged_during_run'] = manifest == source_manifest(root)
        result['finished_utc'] = stamp()
        result['db_observation'] = {'interval_seconds': 2, 'samples': len(observations),
            'max_connections': max((r.get('connections', 0) for r in observations), default=0),
            'max_active': max((r.get('active', 0) for r in observations), default=0),
            'max_lock_waiters': max((r.get('lock_waiters', 0) for r in observations), default=0)}
        with (output / 'requests.jsonl').open('w') as log:
            for row in rows:
                log.write(json.dumps(row) + '\n')
        save(output / 'db-observations.json', observations)
        save(output / 'results.json', result)
        print('Completed:', result.get('completed'), 'cleanup:', result['cleanup'], 'evidence:', output, flush=True)
    return 0 if result.get('completed') and result.get('baseline', {}).get('pass') and result['cleanup']['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
