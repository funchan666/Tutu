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
records=[];manifest=[]
for n,index in enumerate(order):
    src=photos[index]; name=f'editorial-photo-{index+1:03}.jpg';shutil.copy2(src,DEST/name)
    pid,display=primary[n] if n<6 else (f'editorial-{index+1:03}',names[(n-6)%len(names)])
    records.append(dict(id=pid,name=display,handle=f'{display.lower()}.edit{index+1:02}',image='bundle/'+name,video=None,style=['Streetwear','Vintage','Minimalist','Daily'][n%4]))
    manifest.append(dict(source=str(src.relative_to(ROOT)),resource=name,personID=pid,sha256=hashlib.sha256(src.read_bytes()).hexdigest()))
for n,src in enumerate(videos):
    name=f'editorial-video-{n+1:02}.mp4'; poster=f'editorial-video-{n+1:02}.jpg';shutil.copy2(src,DEST/name)
    subprocess.run(['ffmpeg','-y','-v','error','-ss','0.5','-i',str(src),'-frames:v','1','-q:v','3',str(DEST/poster)],check=True)
    pid=f'film-{n+1:02}';display=names[n]
    record=dict(id=pid,name=display,handle=f'{display.lower()}.motion{n+1:02}',image='bundle/'+poster,video='bundle/'+name,style=['Daily','Streetwear','Minimalist','Vintage'][n%4])
    records.insert(min(n*5+3,len(records)),record)
    manifest.append(dict(source=str(src.relative_to(ROOT)),resource=name,poster=poster,personID=pid,sha256=hashlib.sha256(src.read_bytes()).hexdigest()))
(DEST/'EditorialCatalog.json').write_text(json.dumps(records,indent=2)+'\n')
(ROOT/'Docs/ContentMapping.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Packaged {len(photos)} photos + {len(videos)} videos; {len(records)} separate editorial identities.')
