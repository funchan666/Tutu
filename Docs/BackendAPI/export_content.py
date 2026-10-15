"""Offline export of preserved pre-integration constants; no App or HTTP execution."""
import json,re,hashlib
from pathlib import Path
root=Path(__file__).resolve().parent
src=root/'sources'
def read(n): return (src/(n+'.swift.txt')).read_text()
def quoted(s): return json.loads('"'+s+'"')
def strings(s): return [quoted(x) for x in re.findall(r'"((?:[^"\\]|\\.)*)"',s)]
def save(n,data):
 (root/'responses'/f'{n}.json').write_text(json.dumps({'code':0,'message':'ok','data':data},ensure_ascii=False,separators=(',',':')))
items=json.loads((src/'EditorialCatalog.json').read_text()); byid={i['id']:i for i in items}
m=read('Models'); c=read('CoinEconomy'); w=read('WalletService'); st=read('StylistService'); rv=read('RoomViews')
rooms=[]
for ident,title,category,count in re.findall(r'\("([^"]+)", "([^"]+)", "([^"]+)", (\d+)\)',m.split('let selections = [')[1].split(']')[0]):
 item=byid[ident]; rooms.append(dict(id='room-'+ident,hostID=ident,title=title,category=category,voice=False,isBroadcasting=True,video=item['video'],viewerCount=int(count),seats=8,cover=item['image'],localOnly=True))
for ident,title,topic,count in re.findall(r'\("([^"]+)", "([^"]+)", "([^"]+)", (\d+)\)',m.split('let voiceSelections:')[1].split('= [')[1].split(']')[0]):
 item=byid[ident]; interest=item.get('profile',{}).get('interests',[item['style']])[0]
 rooms.append(dict(id='room-'+ident,hostID=ident,title=title,category=interest if interest in ['Daily','Streetwear','Minimalist','Chic'] else 'Daily',voice=True,voiceTopic=topic,isBroadcasting=True,viewerCount=int(count),seats=8,cover=item.get('avatar') or item['image'],localOnly=True))
gifts=[dict(id=a,name=b,price=int(c)) for a,b,c in re.findall(r'\.init\(id: "([^"]+)", name: "([^"]+)", price: (\d+)\)',m)]
packs=[dict(id=a,coins=int(b),referenceUSD=c) for a,b,c in re.findall(r'\.init\(id: "([^"]+)", coins: (\d+), referenceUSD: "([^"]+)"\)',w)]
styles=[dict(name=a,image=b,detail=c) for a,b,c in re.findall(r'StyleDirection\(name: "([^"]+)", image: "([^"]+)", detail: "([^"]+)"\)',st)]
topics=[]
for keys,answers,zh in re.findall(r'Topic\(keys: \[(.*?)\], answers: \[(.*?)\], chinese: "((?:[^"\\]|\\.)*)"\)',st,re.S):
 topics.append(dict(keys=strings(keys),answers=strings(answers),chinese=quoted(zh)))
formulas=dict(re.findall(r'"([^"]+)": "([^"]+)"',st.split('static let formulas:')[1].split('static func reply')[0]))
finishes=strings(st.split('let finish = [')[1].split('][previous')[0])
captions=strings(rv.split('let captions = [')[1].split(']')[0])
rankings=[dict(id=a,daily=int(b),weekly=int(d),total=int(e)) for a,b,d,e in re.findall(r'\(id: "([^"]+)", daily: (\d+), weekly: (\d+), total: (\d+)\)',c)]
reasons=strings(re.search(r'ForEach\(\[("Harassment.*?\])',read('SettingsViews')).group(1))
people=[i for i in items if not i.get('reservedForProfile')]
settings=dict(gifts=gifts,packs=packs,styles=styles,topics=topics,formulas=formulas,finishes=finishes,roomCaptions=captions,rankings=rankings,roomCategories=strings(m.split('static let options = [')[1].split(']')[0]),voiceTopics=strings(m.split('static let options = [')[2].split(']')[0]),reportReasons=reasons,discoverIDs=['look-'+x for x in strings(m.split('static let discoverIDs = [')[1].split(']')[0])],counters={item['id']:dict(followers=12+i*7,following=8+i*3) for i,item in enumerate(people)})
assert len(rooms)==24 and len(gifts)==8 and len(packs)==9 and len(styles)==8 and len(topics)==14 and len(rankings)==10 and len(reasons)==6
save('editorial',items); save('rooms',rooms); save('atelier',settings)
manifest={'sourceFiles':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in src.iterdir()},'counts':{'editorial':len(items),'rooms':len(rooms),'gifts':len(gifts),'packs':len(packs),'styles':len(styles),'topics':len(topics),'comments':sum(len(i.get('comments',[])) for i in items)},'ids':[i['id'] for i in items],'media':sorted(set(x for i in items for x in [i['image'],i.get('avatar'),i.get('video'),*(i.get('photos') or [])] if x))}
(root/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print(manifest['counts'])
