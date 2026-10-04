"""Bounded hosted business reads, authorized ben.demo login and logout only.
Uses ignored backend/.env.demo. Never stores secrets, item IDs or response bodies.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import time
import httpx
from dotenv import dotenv_values


def stats(rows):
    values = sorted(r['elapsed_ms'] for r in rows)
    def p(n):return values[max(0,math.ceil(len(values)*n)-1)] if values else None
    return {'requests':len(rows),'failures':sum(not r['ok'] for r in rows), 'p50_ms':p(.5),'p95_ms':p(.95),'p99_ms':p(.99),'max_ms':max(values,default=None)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    out=args.output
    out.mkdir(parents=True,exist_ok=False)
    values=dotenv_values(args.root/'backend/.env.demo')
    password=values.get('DEMO_USER_PASSWORD')
    if not password:raise RuntimeError('Ignored demo credentials missing')
    base='https://sayfridge-backend-preview.vercel.app/api/v1'
    record={'started_utc':datetime.now(timezone.utc).isoformat(),'api':base,
            'client_location':'Auckland, New Zealand; operator Mac',
            'transport':'HTTPS from operator internet connection to Vercel; existing Neon database',
            'account':'ben.demo (existing ordinary demonstration account)',
            'scope':'120 authenticated GETs at no more than 1 request/second; login/logout create/revoke only this test session; no business writes',
            'harness_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'connection_reuse':True,'timeout_seconds':20,'rows':[]}
    refresh=None
    def request(client,scenario,method,path,**kwargs):
        start=time.perf_counter();row={'scenario':scenario,'method':method,'utc':datetime.now(timezone.utc).isoformat()}
        try:
            response=client.request(method,path,**kwargs)
            row.update(elapsed_ms=round((time.perf_counter()-start)*1000,3),status=response.status_code)
            data=response.json() if response.content else None
            row['ok']=response.status_code==(204 if scenario=='logout' else 200)
        except Exception as exc:
            row.update(elapsed_ms=round((time.perf_counter()-start)*1000,3),status=None,ok=False,error_type=type(exc).__name__);data=None
        return data,row
    try:
        with httpx.Client(base_url=base,timeout=20,trust_env=False) as client:
            version,row=request(client,'version','GET','/system/version')
            record['deployed_version']=version if row['ok'] else None
            record['version_request']=row
            login,row=request(client,'login','POST','/auth/login',json={'email':'ben.demo@example.com','password':password})
            record['login']=row
            if not row['ok'] or not login or not login.get('refresh_token'):
                raise RuntimeError('Hosted login failed')
            refresh=login['refresh_token']
            headers={'Authorization':'Bearer '+login['access_token']}
            inventory,row=request(client,'inventory_setup','GET','/inventory-items?page_size=20',headers=headers)
            record['inventory_setup']=row
            if not row['ok'] or not inventory or not inventory.get('items'):
                raise RuntimeError('No inventory available for representative detail sample')
            record['account_inventory_batches']=inventory['total']
            record['account_first_page_items']=len(inventory['items'])
            item=inventory['items'][0]
            as_of=datetime.now().date().isoformat()
            scenarios=[('inventory_list','/inventory-items?page_size=20'),
                       ('inventory_search','/inventory-items?q='+httpx.QueryParams({'q':item['item_definition_name']}).get('q','')),
                       ('inventory_space_filter','/inventory-items?storage_space_id='+item['storage_space_id']+'&page_size=20'),
                       ('inventory_detail','/inventory-items/'+item['id']),
                       ('operation_history_page','/inventory-operations?page_size=20'),
                       ('expiry_summary','/inventory-items/expiry-summary?as_of='+as_of+'&page_size=20')]
            # Warm-up each endpoint separately; first observation is not labelled a cold start.
            for name,path in scenarios:
                time.sleep(1)
                body,row=request(client,name,'GET',path,headers=headers)
                row['phase']='warmup'
                record['rows'].append(row)
            previous_start=0
            started=time.perf_counter()
            for i in range(120):
                time.sleep(max(0,previous_start+1-time.perf_counter()))
                previous_start=time.perf_counter()
                name,path=scenarios[i%len(scenarios)]
                body,row=request(client,name,'GET',path,headers=headers)
                row['phase']='sample'
                if row['ok']:
                    if name=='inventory_detail':
                        row['ok']=body.get('id')==item['id'] and body.get('storage_space_id')==item['storage_space_id']
                    else:
                        row['ok']=isinstance(body.get('items'),list) and isinstance(body.get('total'),int)
                        if name=='inventory_space_filter':row['ok'] &= all(v['storage_space_id']==item['storage_space_id'] for v in body['items'])
                        if name=='inventory_search':row['ok'] &= all(item['item_definition_name'].lower() in v['item_definition_name'].lower() for v in body['items'])
                record['rows'].append(row)
                if (i+1)%30==0:print('Hosted read samples',i+1,'/120',flush=True)
                if row.get('status')==401:raise RuntimeError('Hosted session ended during samples')
            record['sample_duration_seconds']=round(time.perf_counter()-started,3)
            record['completed']=True
    except Exception as exc:
        record.update(completed=False,error_type=type(exc).__name__)
    finally:
        if refresh:
            with httpx.Client(base_url=base,timeout=20,trust_env=False) as client:
                _,row=request(client,'logout','POST','/auth/logout',json={'refresh_token':refresh})
                record['logout']=row
        samples=[r for r in record['rows'] if r['phase']=='sample']
        record['summary']=stats(samples)
        record['scenarios']={name:stats([r for r in samples if r['scenario']==name]) for name in sorted({r['scenario'] for r in samples})}
        record['finished_utc']=datetime.now(timezone.utc).isoformat()
        (out/'results.json').write_text(json.dumps(record,indent=2)+'\n')
        print('Hosted completed',record.get('completed'),'summary',record['summary'],'logout',record.get('logout',{}).get('ok'),flush=True)
    return 0 if record.get('completed') and record['summary']['failures']==0 and record.get('logout',{}).get('ok') else 1

if __name__=='__main__':raise SystemExit(main())
