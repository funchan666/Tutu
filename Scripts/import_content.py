"""Package every supplied content file unchanged; derive video posters only."""
from pathlib import Path
import json, shutil, subprocess, hashlib
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'Tutu/Resources/Content'; DEST.mkdir(parents=True,exist_ok=True)
photos=sorted((ROOT/'picss').glob('*.jpg')); videos=sorted((ROOT/'videoss').glob('*.mp4'))
# Separate editorial identities for unrelated files; no visual identity matching.
first=[1,2,3,27,5,21]
order=first+[i for i in range(len(photos)) if i not in first]
primary=[('mia','Mia'),('lily','Lily'),('ella','Ella'),('noah','Noah'),('ava','Ava'),('leo','Leo')]
names=['Harper','Riley','Alex','Jordan','Quinn','Sky','Avery','Taylor','Blair','Sage','Cameron','Morgan','Casey','Reese','Rowan','Robin','Jamie','Drew','Charlie','Parker','Remy','River','Emery','Phoenix']
# Curated supplied portraits for room hosts; these are editorial associations, not identity matching.
host_portraits={1:31,2:45,4:61,7:24,9:28,11:3}
host_profiles=json.loads((ROOT/'Scripts/host_profiles.json').read_text())["profiles"]
records=[];manifest=[]
for n,index in enumerate(order):
    src=photos[index]; name=f'editorial-photo-{index+1:03}.jpg';shutil.copy2(src,DEST/name)
    pid,display=primary[n] if n<6 else (f'editorial-{index+1:03}',names[(n-6)%len(names)])
    records.append(dict(id=pid,name=display,handle=f'{display.lower()}.edit{index+1:02}',image='bundle/'+name,video=None,style=['Streetwear','Vintage','Minimalist','Daily'][n%4]))
    manifest.append(dict(source=str(src.relative_to(ROOT)),resource=name,personID=pid,sha256=hashlib.sha256(src.read_bytes()).hexdigest()))
for n,src in enumerate(videos):
    name=f'editorial-video-{n+1:02}.mp4'; poster=f'editorial-video-{n+1:02}.jpg';shutil.copy2(src,DEST/name)
    # The six homepage rooms use the first decoded frame, without a seek.
    seek=[] if n+1 in {1,2,4,7,9,11} else ['-ss','0.5']
    subprocess.run(['ffmpeg','-y','-v','error',*seek,'-i',str(src),'-frames:v','1','-q:v','2',str(DEST/poster)],check=True)
    pid=f'film-{n+1:02}';display=names[n]
    record=dict(id=pid,name=display,handle=f'{display.lower()}.motion{n+1:02}',image='bundle/'+poster,video='bundle/'+name,style=['Daily','Streetwear','Minimalist','Vintage'][n%4])
    if n+1 in host_portraits:
        record["avatar"]=f'bundle/editorial-photo-{host_portraits[n+1]:03}.jpg'
        record["photos"]=[record["avatar"],record["image"]]
    if pid in host_profiles: record["profile"]=host_profiles[pid]
    records.insert(min(n*5+3,len(records)),record)
    manifest.append(dict(source=str(src.relative_to(ROOT)),resource=name,poster=poster,posterTime=0 if n+1 in {1,2,4,7,9,11} else 0.5,personID=pid,sha256=hashlib.sha256(src.read_bytes()).hexdigest()))
(DEST/'EditorialCatalog.json').write_text(json.dumps(records,indent=2)+'\n')
(ROOT/'Docs/ContentMapping.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Packaged {len(photos)} photos + {len(videos)} videos; {len(records)} separate editorial identities.')
