#!/usr/bin/env python3
"""Read-only source/build-graph preflight. Never runs the SDK or a simulator."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
from openstep_read import parse

BASE='857e81b501eb5ed68fbd54fb704948fe422c5f9b'
UNIT='459DAB71243E329F0011ECF3'; SDK='459DAB68243E329F0011ECF3'
SAMPLE='454EF63B24E5CC580070581E'; INTEGRATION='6A8A603E29DAD363008EC7D8'
HOST='8C02E4754875A5B60679B3A0'

def require(ok, reason):
    if not ok: raise ValueError(reason)
def configs(objects,target):
    return {objects[c]['name']:objects[c] for c in objects[objects[target]['buildConfigurationList']]['buildConfigurations']}
def projection(source, enabled):
    """Select only this patch's conditional; preserve unrelated platform directives."""
    result=[]; stack=[]; active=True
    for line in source.splitlines(keepends=True):
        match=re.match(r'\s*#(if|ifdef|ifndef|else|elif|endif)\b(.*)',line)
        if not match:
            if active: result.append(line)
            continue
        op,expr=match.groups()
        if op in ('if','ifdef','ifndef'):
            ours='QN_UNIT_TEST_ISOLATION' in expr
            branch=enabled
            if op=='ifndef' or expr.strip().startswith('!'): branch=not branch
            stack.append((ours,active,branch))
            if ours: active=active and branch
            elif active: result.append(line)
        elif op=='else':
            ours,parent,branch=stack[-1]
            if ours: active=parent and not branch
            elif active:result.append(line)
        elif op=='elif':
            require(not stack[-1][0],'Unsupported isolation elif')
            if active:result.append(line)
        else:
            ours,parent,_=stack.pop()
            if not ours and active: result.append(line)
            active=parent
    require(not stack,'Unbalanced preprocessing conditionals')
    return ''.join(result)
def tokens(source):
    parts=re.findall(r'"""[\s\S]*?"""|@?"(?:\\.|[^"\\])*"|/\*[\s\S]*?\*/|//[^\n]*|\S',source)
    return [part for part in parts if not part.startswith(('/*','//'))]
def validate_graph(objects, scheme, baseline):
    require(objects[HOST]['name']=='QonversionUnitTestHost','Missing dedicated host')
    tests=scheme.findall('./TestAction/Testables/TestableReference/BuildableReference')
    require([t.attrib['BlueprintIdentifier'] for t in tests]==[UNIT],'Unit scheme includes other suite')
    require(scheme.find('TestAction').attrib['buildConfiguration']=='UnitIsolation','Wrong unit configuration')
    seen=set()
    def visit(target):
        if target in seen:return
        seen.add(target)
        for dep in objects[target].get('dependencies',[]):visit(objects[dep]['target'])
    for ref in scheme.findall('./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference'):visit(ref.attrib['BlueprintIdentifier'])
    require(seen=={UNIT,SDK,HOST},'Unexpected build dependency (Sample/watch/integration)')
    for name,cfg in configs(objects,UNIT).items():
        require('QonversionUnitTestHost.app' in cfg['buildSettings']['TEST_HOST'],'Wrong TEST_HOST')
        require(cfg['buildSettings']['BUNDLE_LOADER']=='$(TEST_HOST)','Wrong bundle loader')
    for target in [SDK,UNIT]:
        settings=configs(objects,target)['UnitIsolation']['buildSettings']
        require('QN_UNIT_TEST_ISOLATION=1' in settings['GCC_PREPROCESSOR_DEFINITIONS'],'Missing ObjC isolation flag')
        require('QN_UNIT_TEST_ISOLATION' in settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'],'Missing Swift isolation flag')
    unit_config=configs(objects,UNIT)['UnitIsolation']
    require(objects[unit_config['baseConfigurationReference']]['path']=='UnitTestSupport/Dependencies/Pods/Target Support Files/Pods-QonversionTests/Pods-QonversionTests.unitisolation.xcconfig','Wrong isolated dependency config')
    require(unit_config['buildSettings'].get('PODS_ROOT')=='$(SRCROOT)/UnitTestSupport/Dependencies/Pods','Wrong isolated Pods path')
    require(unit_config['buildSettings'].get('PODS_PODFILE_DIR_PATH')=='$(SRCROOT)/UnitTestSupport/Dependencies','Wrong isolated Podfile path')
    for target in [SAMPLE,INTEGRATION,SDK]:
        for config in ['Debug','Release']:
            require(configs(objects,target)[config]==configs(baseline,target)[config],'Normal target configuration changed')
    source_names={}
    for target in [SDK,UNIT,HOST]:
        names=[]
        for phase in objects[target]['buildPhases']:
            if objects[phase]['isa']!='PBXSourcesBuildPhase':continue
            for entry in objects[phase]['files']:
                names.append(objects[objects[entry]['fileRef']]['path'])
        source_names[target]=names
    require(source_names[HOST]==['UnitTestHost/main.m'],'Host includes secondary application source')
    require('UnitTestSupport/QNUnitIsolationTransport.m' in source_names[SDK],'SDK guard not compiled')
    for name in ['QRequestSerializerTests.m','QonversionTests/Isolation/QNUnitIsolationTests.m','QonversionTests/Isolation/QNUnitIsolationNoCodesTests.swift']:
        require(name in source_names[UNIT],'Required unit test not compiled')
    return {'reachable_targets':len(seen),'unit_testables':len(tests),'host_sources':len(source_names[HOST])}
def verify(root):
    objects=parse((root/'Qonversion.xcodeproj/project.pbxproj').read_text())['objects']
    baseline=parse(subprocess.check_output(['git','show',BASE+':Qonversion.xcodeproj/project.pbxproj'],cwd=root,text=True))['objects']
    scheme=ET.parse(root/'Qonversion.xcodeproj/xcshareddata/xcschemes/QonversionUnitTests.xcscheme').getroot()
    result=validate_graph(objects,scheme,baseline)
    changed=subprocess.check_output(['git','diff','--name-only',BASE,'--','Sources','Framework'],cwd=root,text=True).splitlines()
    checked=[]
    for path in changed:
        old=subprocess.check_output(['git','show',BASE+':'+path],cwd=root,text=True)
        current=projection((root/path).read_text(),False)
        if path.endswith('QNStoreKitService.m'):
            current=re.sub(r'static id QNStoreQueue\(void\)\s*\{\s*return \[SKPaymentQueue defaultQueue\];\s*\}', '',current)
            current=current.replace('QNStoreQueue()','[SKPaymentQueue defaultQueue]')
        if path.endswith('ImagePreloader.swift'):
            current=re.sub(r'  static var defaultSession: URLSession\s*\{\s*return \.shared\s*\}', '',current)
            current=current.replace('urlSession: URLSession = ImagePreloader.defaultSession','urlSession: URLSession = .shared')
        require(tokens(current)==tokens(old),'Normal SDK branch differs: '+path)
        checked.append(path)
    acquisitions={
      'Sources/Qonversion/Qonversion/Services/QNAPIClient/QNAPIClient.m':1,
      'Sources/Qonversion/Qonversion/Main/QONRedemptionManager/QONRedemptionManager.m':1,
      'Sources/NoCodes/NetworkLayer/NetworkProvider/NetworkProvider.swift':2,
      'Sources/NoCodes/Assemblies/ServicesAssembly.swift':1,
      'Sources/NoCodes/Services/ImagePreloader.swift':1,
    }
    for path,count in acquisitions.items():
        isolated=projection((root/path).read_text(),True)
        require(not re.search(r'(?:\[NSURLSession sessionWithConfiguration|URLSession\(configuration:|URLSession\.shared|return \.shared)',isolated),'Unguarded SDK session: '+path)
        calls=re.findall(r'QNUnitIsolationTransport(?: sessionWithConfiguration:|\.session\(|\.sharedSession\()',isolated)
        require(len(calls)==count,'Session factory coverage changed: '+path)
    for path in ['Sources/Swift/StoreKit2Service.swift','Sources/Swift/PurchasesMapper.swift','Sources/NoCodes/NoCodesViewController.swift']:
        isolated=projection((root/path).read_text(),True)
        require(not re.search(r'Product\.products\(|Transaction\.(all|unfinished|currentEntitlements)|await Storefront.current|WKWebView\(frame:|SFSafariViewController\(|UIApplication.shared.open\(',isolated),'Native platform operation still reachable in unit branch: '+path)
    host=(root/'UnitTestHost/main.m').read_text()
    require(not re.search(r'Qonversion\.h|initWithConfig|NoCodes|AppState|ConfigurationManager|syncStoreKit',host),'Host SDK startup code')
    workspace=ET.parse(root/'QonversionUnitIsolation.xcworkspace/contents.xcworkspacedata').getroot()
    require([item.attrib['location'] for item in workspace.findall('FileRef')]==['group:Qonversion.xcodeproj','group:UnitTestSupport/Dependencies/Pods/Pods.xcodeproj'],'Wrong isolated workspace projects')
    result.update({'normal_source_projections':checked,'sdk_session_sites':sum(acquisitions.values()),'native_runtime_proven':False})
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path.cwd());args=parser.parse_args()
    print(json.dumps({'static_preflight':'PASS',**verify(args.root)},indent=2))
if __name__=='__main__':main()
