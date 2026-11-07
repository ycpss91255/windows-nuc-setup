"""對本次 PS5.1 真實產物做破壞性負例；僅操作記憶體副本。"""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'script' / 'test'))
from requirements_gate import ContractError, validate_report
from verify_deployment import validate_portal, verify_with_retry

FILES = {}
REPORT = {}
BASE = 'https://example.github.io/windows_setup/'
README = '\n'.join('![%s](%smain/%s.svg?style=fixture)' % (name, BASE, name) for name in ('unit', 'integration', 'system', 'coverage'))


def portal_files():
    data = {'main/' + name: value for name, value in FILES.items()}
    data['index.html'] = '<h1>目前程式檢查通過</h1><a href="main/index.html">結果</a><a href="https://github.com/example/windows_setup/blob/main/readme.md">使用說明</a>'.encode()
    data['versions.json'] = b'[]'
    return data


def reader(data):
    return lambda path: data[path.split('?')[0]]


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
        data['unit.svg'] = data['unit.svg'].replace(b'>passed<', b'>failed<')
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
        report['Environment'] = 'Synthetic acceptance fixture'
        data['main/summary.json'] = json.dumps(report).encode()
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
    args = parser.parse_args()
    FILES = {p.name: p.read_bytes() for p in args.artifact_dir.iterdir() if p.is_file()}
    REPORT = json.loads(FILES['summary.json'].decode('utf-8-sig'))
    unittest.main(argv=[sys.argv[0]], verbosity=2)
