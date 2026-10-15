#!/usr/bin/env python3
"""Synthetic all-field fixture; order is intentional, testimony is never sorted."""
import sys, json, base64, hashlib, struct, zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from schema import SCHEMA, generic
out = Path(__file__).resolve().parents[2] / 'LimenKitTests/Fixtures/Compatibility'
assets = out / 'assets'; assets.mkdir(parents=True, exist_ok=True)
def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'\0\xff\0\0\0\xff\0\0\0\0\xff\xff\xff\0')) + chunk(b'IEND', b'')
for name in ['wall.png', 'ink.png']: (assets/name).write_bytes(png)
objects=[b'<</Type /Catalog /Pages 2 0 R>>',b'<</Type /Pages /Kids [3 0 R] /Count 1>>',b'<</Type /Page /Parent 2 0 R /MediaBox [0 0 595.276 841.89] /Contents 4 0 R>>',b'<</Length 23>>\nstream\n0 0 20 20 re 0.5 g f\n\nendstream']
pdf=b'%PDF-1.4\n';offsets=[0]
for i,obj in enumerate(objects,1):offsets.append(len(pdf));pdf+=f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n'
xref=len(pdf);pdf+=b'xref\n0 5\n0000000000 65535 f \n'+b''.join(f'{n:010d} 00000 n \n'.encode() for n in offsets[1:])+f'trailer\n<</Size 5 /Root 1 0 R>>\nstartxref\n{xref}\n%%EOF\n'.encode()
for name in ['lease.pdf','retained.pdf']: (assets/name).write_bytes(pdf)
(assets/'retained.html').write_text('<!doctype html><html lang="en"><title>Synthetic retained copy</title><body><h1>Fixture</h1><p>Exact retained bytes</p></body></html>')
enums=dict(Appliance='Oven',DeliveryMethod='Electronic',DepositKind='Unknown',DocumentKind='Lease',DossierCard='Keys',FixBy='Landlord',Furniture='Desk',Grade='Fair',GradeStyle='Grades',ItemKey='Floor',KeyKind='HouseDoor',KeyTransferStatus='Incomplete',Kind='Exit',LegalCheckStatus='ToVerify',LegalRequirement='InitialRentForm',ObjectGroup='Appliance',PhotoSource='Gallery',Plane='Record',Role='Tenant',RoomFixture='Fridge',RoomKind='Kitchen',SwissCanton='NE',TenantResponse='NormalWear',UnilateralReason='OtherPartyAbsent')
def value(typ,name='',owner=''):
    if typ.endswith('?'): return value(typ[:-1],name,owner)
    if g:=generic(typ):
        if g[0]=='Map':
            keys=['z\\"é', 'a🗝'] if g[1][0]=='String' else [value(g[1][0])]
            return {k:value(g[1][1],name,owner) for k in keys}
        return [value(g[1][0],name,owner)]
    if typ in SCHEMA:return {f:value(t,f,typ) for f,t,_,_ in SCHEMA[typ]}
    if typ=='Boolean':return True
    if typ in ['Int','Long']:return 3
    if typ=='String':
        if name=='file':return 'ink.png' if owner=='Signature' else 'lease.pdf' if owner=='SupportingDocument' else 'wall.png'
        if name=='photos':return 'wall.png'
        if name=='sha256':return ''
        if name=='mime':return 'application/pdf'
        if name=='source':return 'https://example.test/lifespan'
        if name=='schema':return 2
        if name in ['handoverDate','lastProtocolDate','date','discoveredDate','notifiedDate','conclusionDate','startDate','endDate','noticeDate','actualTransferDate']:return '2026-10-13'
        if name in ['time','handoverTime','actualTransferTime']:return '10:30'
        if name=='checkedOn':return '2026-10-13'
        return f'{owner}.{name} é \\" 🗝\n'
    return enums[typ]
p=value('Protocol');p['schema']=2;p['id']='source';p['sessionRole']='Tenant';p['evidenceFingerprint']='';p['createdEpochMs']=1791885600000;p['contentRevision']=3
p['parties']=[];p['signatures']=[];p['deliveryReceipts']=[]
for id,role,name in [('tenant-a','Tenant','Ana Example'),('tenant-b','Tenant','Bo Example'),('owner','Landlord','Owner Example')]:
    party=value('Party');party.update(id=id,role=role,name=name,representedBy='Agency Representative' if role=='Landlord' else '',agency='Agency Example' if role=='Landlord' else '',authority='Written mandate reviewed' if role=='Landlord' else '')
    p['parties'].append(party)
    sig=value('Signature');sig.update(participantId=id,role=role,name=party['representedBy'] or name,refused=False,reservation=f'Reservation {id}',contentRevision=3,outcome='')
    p['signatures'].append(sig)
    receipt=value('DeliveryReceipt');receipt.update(participantId=id,role=role);p['deliveryReceipts'].append(receipt)
p['defects'][0]['participantPositions']={'tenant-b':{'response':'NormalWear','comment':'Wear only'},'tenant-a':{'response':'Disputes','comment':'Already present'}}
p['details']['reservations']={'tenant-b':'Second reservation','tenant-a':'First reservation','owner':'Owner reservation'}
p['exportHistory']=[dict(uri='retained.pdf',name='retained.pdf',bytes=len(pdf),language='En',deliveryRevision=2,epochMs=1791885600100,companionUri='retained.html',sha256=hashlib.sha256(pdf).hexdigest().upper())]
p['details']['legalSnapshot'].update(ruleSetId='ch-tenancy-2026.2',profile='FederalAndLease',initialRentFormRule='ConditionalLocal')
(out/'input.json').write_text(json.dumps(p,ensure_ascii=False,indent=2))
