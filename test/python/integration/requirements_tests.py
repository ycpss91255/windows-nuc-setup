"""對本次 PS5.1 真實產物做破壞性負例；僅操作記憶體副本。"""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'script' / 'test'))
from requirements_gate import ContractError, validate_report, badge_status
from verify_deployment import validate_portal, verify_with_retry

FILES = {}
REPORT = {}
PORTAL_FIXTURE = None
BASE = 'https://example.github.io/windows_setup/'
README = '\n'.join('![%s](%smain/%s.svg?style=fixture)' % (name, BASE, name) for name in ('unit', 'integration', 'system', 'coverage'))


def portal_files():
    data = {'main/' + name: value for name, value in FILES.items()}
    conclusion = '目前程式檢查通過' if REPORT['Success'] else '目前程式檢查未通過'
    data['index.html'] = ('<h1>' + conclusion + '</h1><a href="main/index.html">結果</a><a href="https://github.com/example/windows_setup/blob/main/readme.md">使用說明</a>').encode()
    data['versions.json'] = b'[]'
    return data


def reader(data):
    return lambda path: data[path.split('?')[0]]


def synthetic_badge(report, name):
    # Memory-only shape fixture. Real renderer bytes are separately checked by test_real_ps51_artifact.
    label = name + ' ' + report['RefType'].lower()
    value = badge_status(report, name)
    left, right = len(label) * 7 + 12, len(value) * 7 + 12
    color = {'passed': '#4c1', 'failed': '#e05d44'}.get(value, '#9f9f9f')
    return ('<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%s"><rect width="%s" fill="#555"/><rect width="%s" fill="%s"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>' % (left + right, left, right, color, label, value)).encode()


def synthetic_result(passed, ref_type):
    data = dict(FILES)
    report = copy.deepcopy(REPORT)
    report['RefType'] = ref_type
    report['RefName'] = 'main' if ref_type == 'Branch' else report['Version']
    report['Environment'] = 'Synthetic acceptance fixture'
    report['Success'] = passed
    xml = ET.Element('testsuites')
    for check in report['Checks']:
        if check['Executed']:
            check['Passed'] = True
            check['Status'] = 'Passed'
            check['ExitCode'] = 0
            for assertion in check['Assertions']:
                assertion['Passed'] = True
    if not passed:
        check = next(c for c in report['Checks'] if c['Layer'] == 'Unit' and c['Assertions'])
        check.update(Passed=False, Status='Failed', ExitCode=1)
        check['Assertions'][0]['Passed'] = False
    assertions = [a for c in report['Checks'] if c['Executed'] for a in c['Assertions']]
    report['Totals']['AssertionsPassed'] = sum(a['Passed'] for a in assertions)
    report['Totals']['AssertionsFailed'] = sum(not a['Passed'] for a in assertions)
    for check in report['Checks']:
        suite = ET.SubElement(xml, 'testsuite', name=check['Name'])
        for item in check['Assertions'] or [{'Name': check['Name'], 'Passed': check['Passed']}]:
            case = ET.SubElement(suite, 'testcase', name=item['Name'])
            if not check['Executed']:
                ET.SubElement(case, 'skipped')
            elif not item['Passed']:
                ET.SubElement(case, 'failure')
    data['summary.json'] = json.dumps(report).encode()
    data['junit.xml'] = ET.tostring(xml)
    data['index.html'] = (('<h2>單元與隔離整合測試通過</h2>' if passed else '<h2>本次測試未通過</h2>') + '<a href="summary.json">JSON</a><a href="summary.md">MD</a><a href="junit.xml">JUnit</a>').encode()
    for name in ('unit', 'integration', 'system', 'coverage'):
        data[name + '.svg'] = synthetic_badge(report, name)
    return data


class RequirementsTests(unittest.TestCase):
    def report(self, data):
        return validate_report(reader(data), REPORT['Commit'], REPORT['RunUrl'])

    def test_real_ps51_artifact(self):
        self.assertEqual(self.report(FILES)['Commit'], REPORT['Commit'])

    def test_wrong_sha_rejected(self):
        with self.assertRaises(ContractError):
            validate_report(reader(FILES), '0' * 40, REPORT['RunUrl'])

    def test_wrong_run_rejected(self):
        with self.assertRaises(ContractError):
            validate_report(reader(FILES), REPORT['Commit'], REPORT['RunUrl'] + '0')

    def test_inconsistent_total_rejected(self):
        data = dict(FILES)
        report = copy.deepcopy(REPORT)
        report['Totals']['AssertionsPassed'] += 1
        data['summary.json'] = json.dumps(report).encode()
        with self.assertRaises(ContractError):
            self.report(data)

    def test_system_false_pass_rejected(self):
        data = dict(FILES)
        report = copy.deepcopy(REPORT)
        next(c for c in report['Checks'] if c['Layer'] == 'System')['Passed'] = True
        data['summary.json'] = json.dumps(report).encode()
        with self.assertRaises(ContractError):
            self.report(data)

    def test_old_badge_geometry_rejected(self):
        data = dict(FILES)
        data['unit.svg'] = data['unit.svg'].replace(b'height="20"', b'height="24"')
        with self.assertRaises(ContractError):
            self.report(data)

    def test_badge_false_failure_rejected(self):
        data = dict(FILES)
        status = badge_status(REPORT, 'unit')
        wrong = 'passed' if status != 'passed' else 'failed'
        data['unit.svg'] = data['unit.svg'].replace(('>' + status + '<').encode(), ('>' + wrong + '<').encode())
        with self.assertRaises(ContractError):
            self.report(data)

    def test_missing_evidence_link_rejected(self):
        data = dict(FILES)
        data['index.html'] = data['index.html'].replace(b'href="junit.xml"', b'href="missing.xml"')
        with self.assertRaises(ContractError):
            self.report(data)

    def test_raw_unknown_rejected(self):
        data = dict(FILES)
        data['index.html'] += b'<p>Unknown</p>'
        with self.assertRaises(ContractError):
            self.report(data)

    def test_technical_unknown_inside_closed_details_allowed(self):
        data = dict(FILES)
        data['index.html'] += b'<details><summary>Technical details</summary><p>assertion: Unknown remains Unknown</p></details>'
        self.assertEqual(self.report(data)['Commit'], REPORT['Commit'])

    def test_unknown_inside_open_details_rejected(self):
        data = dict(FILES)
        data['index.html'] += b'<details open><summary>Details</summary><p>Unknown</p></details>'
        with self.assertRaises(ContractError):
            self.report(data)

    def test_private_path_rejected(self):
        data = dict(FILES)
        data['summary.md'] += b'\nC:\\Users\\fixture_person\\secret'
        with self.assertRaises(ContractError):
            self.report(data)

    def synthetic_main(self):
        # Memory-only fixture, never uploaded or represented as real main evidence.
        data = portal_files()
        report = copy.deepcopy(REPORT)
        report['RefName'] = 'main'
        report['RefType'] = 'Branch'
        report['Environment'] = 'Synthetic acceptance fixture'
        data['main/summary.json'] = json.dumps(report).encode()
        for name in ('unit', 'integration', 'system', 'coverage'):
            data['main/' + name + '.svg'] = synthetic_badge(report, name)
        return data

    def test_synthetic_main_portal_contract(self):
        report = validate_portal(reader(self.synthetic_main()), README, REPORT['Commit'], REPORT['RunUrl'], BASE)
        self.assertEqual(report['Environment'], 'Synthetic acceptance fixture')

    def test_broken_primary_link_rejected(self):
        data = self.synthetic_main()
        data['index.html'] = data['index.html'].replace(b'main/index.html', b'missing.html')
        with self.assertRaises(ContractError):
            validate_portal(reader(data), README, REPORT['Commit'], REPORT['RunUrl'], BASE)

    def test_missing_readme_badge_rejected(self):
        with self.assertRaises(ContractError):
            validate_portal(reader(self.synthetic_main()), '', REPORT['Commit'], REPORT['RunUrl'], BASE)

    def test_missing_history_real_wording_contract(self):
        data = self.synthetic_main()
        data['versions.json'] = json.dumps([{'Version': 'v0.1.0', 'Status': 'Unknown', 'Path': 'versions/v0.1.0/index.html'}]).encode()
        data['versions/v0.1.0/index.html'] = '<h1>這個版本未保存可用的測試紀錄</h1><p>未提供可驗證品質快照</p>'.encode()
        data['comparisons/v0.1.0--v0.1.0.json'] = b'{"Status":"Unknown"}'
        self.assertEqual(validate_portal(reader(data), README, REPORT['Commit'], REPORT['RunUrl'], BASE)['RefName'], 'main')

    def test_actual_generated_portal_with_missing_history(self):
        require_fixture = PORTAL_FIXTURE
        self.assertIsNotNone(require_fixture, 'Actual PowerShell portal fixture is required, not a mocked HTML template')
        report = json.loads((require_fixture / 'main/summary.json').read_text(encoding='utf-8-sig'))
        self.assertIn('Synthetic acceptance fixture', report['Environment'])
        checked = validate_portal(lambda path: (require_fixture / path.split('?')[0]).read_bytes(), README, report['Commit'], report['RunUrl'], BASE)
        self.assertEqual(checked['Commit'], 'f' * 40)

    def test_truthful_failed_branch_report_is_valid_evidence(self):
        self.assertFalse(self.report(synthetic_result(False, 'Branch'))['Success'])

    def test_passing_branch_and_release_shapes(self):
        for ref_type in ('Branch', 'Release'):
            with self.subTest(ref_type=ref_type):
                self.assertTrue(self.report(synthetic_result(True, ref_type))['Success'])

    def test_pr_not_relabelled_as_main(self):
        data = portal_files()
        report = copy.deepcopy(REPORT)
        report['RefName'] = '5/merge'
        data['main/summary.json'] = json.dumps(report).encode()
        with self.assertRaises(ContractError):
            validate_portal(reader(data), README, REPORT['Commit'], REPORT['RunUrl'], BASE)

    def test_finite_retry_does_not_accept_stale_sha(self):
        calls = []
        def missing(path):
            calls.append(path)
            return FILES[path.removeprefix('main/')]
        with self.assertRaises(ContractError):
            verify_with_retry(missing, README, '0' * 40, REPORT['RunUrl'], BASE, attempts=3, delay=0, sleep=lambda _: None)
        self.assertEqual(len(calls), 3)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifact-dir', type=Path, required=True)
    parser.add_argument('--portal-fixture-dir', type=Path, required=True)
    args = parser.parse_args()
    FILES = {p.name: p.read_bytes() for p in args.artifact_dir.iterdir() if p.is_file()}
    REPORT = json.loads(FILES['summary.json'].decode('utf-8-sig'))
    PORTAL_FIXTURE = args.portal_fixture_dir
    unittest.main(argv=[sys.argv[0]], verbosity=2)
