"""Copy supplied design assets non-destructively into semantic asset catalogs."""
import json, shutil
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1]
source=root/'sucai'; dest=root/'Tutu/Resources/Assets.xcassets'
mapping={
'brand-mascot':'image 75','screen-background':'Group 903','welcome-background':'Group 940','profile-background':'Group 920','checkin-background':'Group 1024','leaderboard-background':'Group 994',
'heading-style-live':'Style Live','heading-party':'Party','heading-studio':'Create Your Look','heading-discover':'Discover','heading-feed':'Feed','heading-profile':'Profile',
'nav-back':'Frame 151','nav-close':'Group 945','nav-more':'Group 927','nav-search':'Group 954','nav-create':'Group 953','nav-settings':'Frame','nav-help':'Frame@2x(21)',
'tab-live-active':'Frame@2x(26)','tab-live':'Frame@2x(29)','tab-party-active':'Frame 176@2x(5)','tab-party':'Frame 176@2x(1)','tab-studio-active':'Frame@2x(7)','tab-studio':'Frame@2x(1)','tab-discover-active':'Frame 178@2x(2)','tab-discover':'Frame 178@2x(5)','tab-profile-active':'Frame 175','tab-profile':'Frame 177@2x(1)',
'control-content-follow':'Group 957','control-content-followed':'Group 956','control-check':'Group 934','control-selected':'Group 933','control-follow':'Group 931','control-tick':'Group 956','control-on':'Group 1019','control-off':'Group 1018',
'button-base':'Group 929','button-email':'Group 941','button-login':'Group 946','button-register':'Group 947','button-next':'Group 948','button-done':'Group 950','button-entry':'Group 951','button-save':'Group 1023','button-edit':'Group 1017','button-checkin':'Group 1025','button-add-photo':'Group 1028','button-generate':'Group 998','button-send':'Group 984','button-create-live':'Group 995','button-create-voice':'Group 998@2x(2)','button-start-live':'Group 996','button-create-room':'Group 999','button-search':'Group 1000','button-join':'Group 1001','button-recharge':'Group 976',
'icon-trophy':'Group 952','icon-photo':'Group 1009','icon-mic':'Group 1010','icon-camera':'Frame@2x(6)','icon-calendar':'Frame@2x(5)','icon-send':'Group 1011','icon-voice-record':'Group 983','icon-gift':'Group 970','icon-room-chat':'Group 962','icon-notification':'Group 1006','icon-support':'Group 1005','icon-female':'Group 905','icon-male':'Group 907','icon-like':'Group 1029','icon-liked':'Group 1032','icon-comment':'Group 1030','icon-content-more':'Group 1031','icon-online':'Group 923','icon-live':'Group 1002','icon-lucky-star':'Rectangle 792','icon-coin':'Rectangle 815@2x(2)','icon-flame':'🔥',
'empty-state':'Group 938','notification-art':'image 82','profile-shortcuts':'Group 918','popup-background':'Group 1020','lucky-star-banner':'Group 959','live-banner':'Group 1003','voice-banner':'Group 1004',
'gift-microphone':'image 100@2x(2)','gift-heart':'image 101@2x(2)','gift-bear':'image 102','gift-castle':'image 103','gift-car':'image 104','gift-flowers':'image 105','gift-star':'image 106@2x(1)','gift-music':'image 107',
'style-minimalist':'Rectangle 965','style-streetwear':'Rectangle 966','style-vintage':'Rectangle 967',
}
# Reviewed unused exports remain in sucai, outside the application bundle.
excluded = {'button-done', 'button-recharge', 'button-start-live', 'icon-online', 'button-create-voice', 'button-send', 'button-next', 'icon-lucky-star', 'button-search', 'icon-calendar', 'button-entry', 'leaderboard-background', 'popup-background', 'button-create-live', 'notification-art', 'heading-feed', 'icon-live', 'icon-support', 'profile-background', 'control-tick'}
dest.mkdir(parents=True,exist_ok=True)
manifest=[]
for name,raw in mapping.items():
 filename=raw+'.png' if '@2x' in raw else raw+'@2x.png'
 f=source/filename
 if not f.exists(): raise FileNotFoundError(f)
 folder=dest/(name+'.imageset')
 if name in excluded:
  if folder.exists(): shutil.rmtree(folder)
  manifest.append({'asset':name,'source':'sucai/'+filename,'size':list(Image.open(f).size),'bundled':False})
  continue
 folder.mkdir(exist_ok=True)
 shutil.copy2(f,folder/'artwork.png')
 (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'artwork.png','idiom':'universal','scale':'2x'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
 manifest.append({'asset':name,'source':'sucai/'+filename,'size':list(Image.open(f).size),'bundled':True})
icon=dest/'AppIcon.appiconset';icon.mkdir(exist_ok=True)
Image.open(source/'image 75@2x.png').convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS).save(icon/'AppIcon.png')
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
color=dest/'LaunchBackground.colorset';color.mkdir(exist_ok=True)
(color/'Contents.json').write_text(json.dumps({'colors':[{'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.000','green':'0.000','blue':'0.000','alpha':'1.000'}}}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
(root/'Docs/AssetMapping.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Imported',len(manifest),'original asset mappings; source files preserved.')
