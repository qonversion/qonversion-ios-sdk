import copy
import importlib.util
from pathlib import Path
import subprocess
import unittest
import xml.etree.ElementTree as ET
import check_unit_isolation as check
from openstep_read import parse

ROOT=Path(__file__).resolve().parents[2]
class IsolationStaticTests(unittest.TestCase):
    def setUp(self):
        self.objects=parse((ROOT/'Qonversion.xcodeproj/project.pbxproj').read_text())['objects']
        self.baseline=parse(subprocess.check_output(['git','show',check.BASE+':Qonversion.xcodeproj/project.pbxproj'],cwd=ROOT,text=True))['objects']
        self.scheme=ET.parse(ROOT/'Qonversion.xcodeproj/xcshareddata/xcschemes/QonversionUnitTests.xcscheme').getroot()
    def validate(self): return check.validate_graph(self.objects,self.scheme,self.baseline)
    def test_current_source_and_graph(self):self.assertFalse(check.verify(ROOT)['native_runtime_proven'])
    def test_sample_host_rejected(self):
        check.configs(self.objects,check.UNIT)['UnitIsolation']['buildSettings']['TEST_HOST']='Sample.app/Sample'
        with self.assertRaisesRegex(ValueError,'TEST_HOST'):self.validate()
    def test_missing_objc_flag_rejected(self):
        check.configs(self.objects,check.SDK)['UnitIsolation']['buildSettings']['GCC_PREPROCESSOR_DEFINITIONS']=[]
        with self.assertRaisesRegex(ValueError,'ObjC'):self.validate()
    def test_missing_swift_flag_rejected(self):
        check.configs(self.objects,check.SDK)['UnitIsolation']['buildSettings']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        with self.assertRaisesRegex(ValueError,'Swift'):self.validate()
    def test_sample_dependency_rejected(self):
        self.objects[check.UNIT]['dependencies'].append('45BD0334257FE394005B7DA0')
        with self.assertRaisesRegex(ValueError,'dependency'):self.validate()
    def test_extra_integration_testable_rejected(self):
        refs=self.scheme.find('./TestAction/Testables'); node=copy.deepcopy(refs[0]);node[0].set('BlueprintIdentifier',check.INTEGRATION);refs.append(node)
        with self.assertRaisesRegex(ValueError,'other suite'):self.validate()
    def test_debug_runtime_configuration_rejected(self):
        self.scheme.find('TestAction').set('buildConfiguration','Debug')
        with self.assertRaisesRegex(ValueError,'configuration'):self.validate()
    def test_missing_transport_source_rejected(self):
        for phase in self.objects[check.SDK]['buildPhases']:
            obj=self.objects[phase]
            if obj['isa']=='PBXSourcesBuildPhase':
                obj['files']=[entry for entry in obj['files'] if self.objects[self.objects[entry]['fileRef']]['path']!='UnitTestSupport/QNUnitIsolationTransport.m']
        with self.assertRaisesRegex(ValueError,'guard not compiled'):self.validate()
    def test_accidental_sample_normal_setting_change_rejected(self):
        check.configs(self.objects,check.SAMPLE)['Debug']['buildSettings']['SDKROOT']='unsafe-change'
        with self.assertRaisesRegex(ValueError,'Normal target'):self.validate()
    def test_source_literal_changes_not_hidden_as_comments(self):
        self.assertNotEqual(check.tokens('return "https://one.invalid/";'),check.tokens('return "https://two.invalid/";'))
    def test_nested_mode_projection_preserves_platform_condition(self):
        src='#if os(iOS)\n#if QN_UNIT_TEST_ISOLATION\nguarded()\n#else\nnative()\n#endif\n#endif\n'
        self.assertEqual(check.projection(src,True),'#if os(iOS)\nguarded()\n#endif\n')
        self.assertEqual(check.projection(src,False),'#if os(iOS)\nnative()\n#endif\n')
    def test_unbalanced_condition_rejected(self):
        with self.assertRaisesRegex(ValueError,'Unbalanced'):check.projection('#if QN_UNIT_TEST_ISOLATION\n',True)
    def test_openstep_duplicate_key_rejected(self):
        with self.assertRaisesRegex(ValueError,'Duplicate'):parse('{ a = b; a = c; }')
if __name__=='__main__':unittest.main(verbosity=2)
