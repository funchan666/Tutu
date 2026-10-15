"""Offline artifact and source-reference audit. Does not compile or run the app."""
from pathlib import Path
import json, hashlib, plistlib, subprocess, re
from urllib.parse import quote
root=Path(__file__).resolve().parent
repo=root.parents[1]
contract=json.loads((root/'contract.json').read_text())
manifest=json.loads((root/'source-manifest.json').read_text())
app_id=contract['sourceAppId']
assert app_id=='75252159' and contract['baseURL']=='https://fjnvs.fdhewhf.top'
interfaces=json.loads((root/'generated'/f'接口模板-{app_id}.json').read_text())
configuration=json.loads((root/'generated'/f'配置模板-{app_id}.json').read_text())
for item in [interfaces,configuration]: assert item['sourceAppId']==app_id
for p in (root/'generated').glob(f'*-{app_id}.json'): assert '\n' not in p.read_text().strip()
responses={x['url']:json.loads(x['responseContent']) for x in interfaces['interfaces']}
assert len(responses)==len(interfaces['interfaces'])==6
for x in interfaces['interfaces']: assert '\n' not in x['responseContent']
for role,path in contract['endpoints'].items(): assert responses[path]==json.loads((root/contract['endpointResponses'][role]).read_text())
for route in contract['contentRoutes']: assert responses[route['path']]==json.loads((root/route['file']).read_text())
source=json.loads((root/'sources/EditorialCatalog.json').read_text())
editorial=responses['/tutu/catalog/editorial']['data']
settings=responses['/tutu/catalog/atelier']['data']
rooms=responses['/tutu/catalog/rooms']['data']
assert editorial==source and [x['id'] for x in editorial]==manifest['ids']
for name,digest in manifest['sourceFiles'].items(): assert hashlib.sha256((root/'sources'/name).read_bytes()).hexdigest()==digest
assert len(editorial)==86 and len(rooms)==24 and sum(len(x.get('comments',[])) for x in editorial)==30
assert len(settings['styles'])==8 and len(settings['gifts'])==8 and len(settings['packs'])==9
ids={x['id'] for x in editorial}; assert len(ids)==86
assert all(r['hostID'] in ids for r in rooms)
assert all(c['authorID'] in ids for x in editorial for c in x.get('comments',[]))
media=set(manifest['media']) | {x['cover'] for x in rooms} | {x['image'] for x in settings['styles']} | {'gift-'+x['id'] for x in settings['gifts']}
resources=repo/'Tutu/Resources'
for ref in media:
 if ref.startswith(('https://','http://')): continue
 elif ref.startswith('bundle/'): assert len(list(resources.rglob(ref.removeprefix('bundle/'))))==1,ref
 else: assert (resources/'Assets.xcassets'/(ref+'.imageset')/'Contents.json').exists(),ref
mapping=json.loads((repo/'Docs/ContentMapping.json').read_text())
aliases=json.loads((resources/'Content/EditorialMediaAliases.json').read_text())
assert len(mapping)==len(aliases)==86
assert sum(x['source'].startswith('picss/') for x in mapping)==74
assert sum(x['source'].startswith('videoss/') for x in mapping)==12
for row in mapping:
 original=Path(row['source'])
 folder={'picss':'pics','videoss':'videoss'}[original.parts[0]]
 expected='https://pub-1e78b29dc9034ab296832bae0193b76c.r2.dev/'+folder+'/'+quote(original.name)
 legacy='bundle/'+row['resource']
 assert row['remoteURL']==aliases[legacy]==expected
 assert row['storage']=='remote' and expected in media and legacy not in media
 assert not (repo/original).exists() and not (resources/'Content'/row['resource']).exists()
assert len(list((resources/'Content').glob('editorial-video-*.jpg')))==12
assert not list((resources/'Content').glob('*.mp4'))
for name in ['picss','videoss']:
 assert not (repo/name).exists() or not list((repo/name).glob('*'))
swift=(repo/'Tutu/Integration/IntegrationContract.swift').read_text()
assert 'static let apiMethod: String = "POST"' in swift
assert contract['baseURL'] in swift
for path in list(contract['endpoints'].values())+[x['path'] for x in contract['contentRoutes']]: assert '"'+path+'"' in swift
for field in list(contract['requestFields'].values())+list(contract['additionalLoginFields'].values()): assert '"'+field+'"' in swift
parameters={x['keyName']:x for x in configuration['parameters']}
for key,value in {**contract['requestFields'],**contract['h5Fields']}.items(): assert parameters[key]['valueName']==value
for key,event in contract['events'].items():
 row=parameters[key]
 assert json.loads(row['messageTemplate'])==event['template']
 assert '\n' not in row['messageTemplate']
plist=plistlib.loads((repo/'Tutu/Info.plist').read_bytes())
assert 'im.seex.sao2' in [scheme for row in plist['CFBundleURLTypes'] for scheme in row['CFBundleURLSchemes']]
for key in ['NSCameraUsageDescription','NSMicrophoneUsageDescription','NSPhotoLibraryUsageDescription']: assert len(plist[key])>15
project=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(repo/'Tutu.xcodeproj/project.pbxproj')]))['objects']
source_ids=[x for o in project.values() if o.get('isa')=='PBXSourcesBuildPhase' for x in o['files']]
source_names={project[project[x]['fileRef']]['path'] for x in source_ids}
for p in (repo/'Tutu').rglob('*.swift'): assert p.name in source_names,p
resource_ids=[x for o in project.values() if o.get('isa')=='PBXResourcesBuildPhase' for x in o['files']]
resource_names={project[project[x]['fileRef']]['path'] for x in resource_ids}
assert 'EditorialMediaAliases.json' in resource_names
assert not ({x['resource'] for x in mapping} & resource_names)
products={o['productName'] for o in project.values() if o.get('isa')=='XCSwiftPackageProductDependency'}
assert {'Ably','Alamofire'}<=products
for o in project.values():
 if o.get('isa')=='XCBuildConfiguration' and 'PRODUCT_BUNDLE_IDENTIFIER' in o['buildSettings']:
  assert o['buildSettings']['PRODUCT_BUNDLE_IDENTIFIER']=='im.seex.sao2'
  assert str(o['buildSettings']['TARGETED_DEVICE_FAMILY'])=='1'
assert not (resources/'Content/EditorialCatalog.json').exists()
assert 'Docs/BackendAPI' not in (repo/'Tutu.xcodeproj/project.pbxproj').read_text()
locks=json.loads((repo/'Tutu.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
versions={x['identity']:x['state']['version'] for x in locks['pins']}
assert versions['ably-cocoa']=='1.4.0' and versions['alamofire']=='5.12.2'
assert not any('datasetVersion' in p.read_text() for p in (root/'responses').glob('*.json'))
print(json.dumps({'interfaces':len(responses),'sourceRecords':len(editorial),'rooms':len(rooms),'comments':30,'mediaReferences':len(media),'targetSwiftFiles':len(source_names),'packages':versions,'result':'Offline artifacts and references consistent; no compilation or runtime verification'},ensure_ascii=False))
