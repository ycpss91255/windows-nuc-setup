"""需求驗收：解析真實產物；不宣稱完成實機或人工視覺驗收。"""
import argparse
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET


class ContractError(ValueError):
    pass


def require(value, message):
    if not value:
        raise ContractError(message)


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.links, self.text, self.hidden = [], [], 0
        self.details = []
        self.visible_links = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'details':
            self.details.append({'open': 'open' in attrs, 'summary': False})
        if tag == 'summary' and self.details:
            self.details[-1]['summary'] = True
        if tag in ('script', 'style'):
            self.hidden += 1
        if tag == 'a' and attrs.get('href'):
            self.links.append(attrs['href'])
            if not self.hidden and all(d['open'] or d['summary'] for d in self.details):
                self.visible_links.append(attrs['href'])

    def handle_endtag(self, tag):
        if tag == 'summary' and self.details:
            self.details[-1]['summary'] = False
        if tag == 'details' and self.details:
            self.details.pop()
        if tag in ('script', 'style') and self.hidden:
            self.hidden -= 1

    def handle_data(self, data):
        if not self.hidden and all(d['open'] or d['summary'] for d in self.details):
            self.text.append(data)

    @property
    def visible(self):
        return ' '.join(self.text)


def badge_status(report, name):
    if name == 'coverage':
        return 'not measured'
    if name == 'system':
        return 'not run'
    rows = [c for c in report['Checks'] if c['Layer'].lower() == name and c['Executed']]
    return 'not run' if not rows else ('passed' if all(c['Passed'] for c in rows) else 'failed')


def validate_svg(data, report, name):
    svg = ET.fromstring(data)
    ns = {'s': 'http://www.w3.org/2000/svg'}
    label = name + ' ' + report['RefType'].lower()
    status = badge_status(report, name)
    texts = svg.findall('.//s:text', ns)
    rects = svg.findall('s:rect', ns)
    require(svg.tag == '{http://www.w3.org/2000/svg}svg', 'R05 SVG 格式不符')
    require(svg.get('height') == '20', 'R05 徽章高度不是 base 的 20px')
    require(len(texts) == 2 and [t.text for t in texts] == [label, status], 'R05 徽章狀態與 JSON 不一致')
    require(svg.find('s:g', ns).get('font-size') == '11', 'R05 徽章字體不是 11px')
    expected_width = (len(label) + len(status)) * 7 + 24
    require(svg.get('width') == str(expected_width), 'R05 徽章寬度未隨文字計算')
    color = {'passed': '#4c1', 'failed': '#e05d44'}.get(status, '#9f9f9f')
    require(len(rects) == 2 and rects[0].get('fill') == '#555' and rects[1].get('fill') == color, 'R05 徽章配色不符真實狀態')
    require(rects[0].get('width') == str(len(label) * 7 + 12) and rects[1].get('width') == str(len(status) * 7 + 12), 'R05 徽章區段寬度不符')


def validate_report(read, expected_sha, expected_run, main=False):
    report = json.loads(read('summary.json').decode('utf-8-sig'))
    require(report['SchemaVersion'] == 1 and report['RequestedLayer'] == 'All', 'R02 缺少完整測試範圍')
    require(report['Commit'] == expected_sha, 'R03 報表提交不是本次預期提交')
    require(report['RunUrl'] == expected_run, 'R03 報表執行來源不是本次執行')
    require(report['SourceState'] == 'Clean', 'R03 報表來源不是乾淨版本')
    if main:
        require(report['RefType'] == 'Branch' and report['RefName'] == 'main', 'R03 部署報表不是 main 分支')
    require(report['Coverage'] == 'NotMeasured', 'R02 覆蓋率不能冒稱已量測')
    checks = report['Checks']
    require(bool(checks), 'R02 不得用空測試集合冒稱成功')
    for layer in ('Unit', 'Integration'):
        require(any(c['Layer'] == layer and c['Executed'] for c in checks), 'R02 必要測試層沒有執行：' + layer)
    for layer in ('System', 'System E2E'):
        rows = [c for c in checks if c['Layer'] == layer]
        require(rows and all(c['Status'] == 'NotRun' and c['Executed'] is False and c['Passed'] is None and not c['Assertions'] for c in rows), 'R02 未執行的實機測試被誤標通過')
    require(report['Success'] is all(c['Passed'] is True for c in checks if c['Executed']), 'R02 整體結果與子測試不一致')
    assertions = [a for c in checks if c['Executed'] for a in c['Assertions']]
    totals = {'SuitesExecuted': sum(c['Executed'] for c in checks), 'AssertionsExecuted': len(assertions), 'AssertionsPassed': sum(a['Passed'] is True for a in assertions), 'AssertionsFailed': sum(a['Passed'] is False for a in assertions), 'UnexecutedSuites': sum(not c['Executed'] for c in checks)}
    require(report['Totals'] == totals, 'R02 統計與逐項證據不一致')
    xml = ET.fromstring(read('junit.xml'))
    suites = xml.findall('testsuite')
    require(len(suites) == len(checks), 'R04 JUnit 套件數量不完整')
    for suite, check in zip(suites, checks):
        cases = suite.findall('testcase')
        require(suite.get('name') == check['Name'] and bool(cases), 'R04 JUnit 套件與 JSON 不一致')
        if not check['Executed']:
            require(all(c.find('skipped') is not None and c.find('failure') is None for c in cases), 'R02 JUnit 未執行狀態不一致')
        else:
            require((not any(c.find('failure') is not None for c in cases)) == check['Passed'], 'R02 JUnit 成敗與 JSON 不一致')
    page = Page(read('index.html').decode('utf-8-sig'))
    require({'summary.json', 'summary.md', 'junit.xml'}.issubset(page.links), 'R04 報表缺少可點擊的證據連結')
    require(('單元與隔離整合測試通過' if report['Success'] else '本次測試未通過') in page.visible, 'R02 明細結論與 JSON 不一致')
    require('Unknown' not in page.visible, 'R06 前台出現未翻譯 Unknown')
    md = read('summary.md').decode('utf-8-sig')
    require(expected_sha in md and report['MeasuredAt'] in md, 'R03 文字摘要來源或時間不一致')
    for name in ('unit', 'integration', 'system', 'coverage'):
        validate_svg(read(name + '.svg'), report, name)
    for name in ('summary.json', 'summary.md', 'index.html', 'junit.xml'):
        text = read(name).decode('utf-8-sig')
        require(not re.search(r'(?<![A-Za-z])(?:[A-Za-z]:\\(?:Users|actions|a|Windows)\\|/home/runner/|/Users/[^/]+/)', text, re.I), 'R07 公開產物包含本機或 runner 絕對路徑')
    return report


def validate_source(root):
    import subprocess
    paths = subprocess.check_output(['git', '-C', str(root), '-c', 'core.quotePath=false', 'ls-files'], text=True, encoding='utf-8').splitlines()
    for path in paths:
        if not path.startswith('modules/debloat/win11debloat/'):
            require(re.fullmatch(r'[a-z0-9_.]+', Path(path).name), 'R08 自有檔名不是小寫底線：' + path)
    readme = (root / 'readme.md').read_text(encoding='utf-8-sig')
    for target in re.findall(r'\]\(([^)]+)\)', readme):
        if not target.startswith(('http:', 'https:', '#')):
            target = target.split('#')[0]
            require(target in paths, 'R01 README 相對連結不存在或大小寫不符：' + target)
    ci_badges = re.findall(r'https://github\.com/[^/]+/[^/]+/actions/workflows/([^/]+)/badge\.svg', readme)
    require(len(ci_badges) == 1 and '.github/workflows/' + ci_badges[0] in paths, 'R05 README Windows CI 徽章沒有對應 workflow')
    for entry in ('init.cmd', 'windows.cmd'):
        require(entry in paths and entry in readme, 'R01 缺少使用者入口：' + entry)
    require('Ctrl+Shift+F3' in readme and '-AfterRestart' in readme and '-VerifyOnly' in readme, 'R01 操作說明缺少初始化或重開後步驟')
    return readme


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifact-dir', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--expected-sha', required=True)
    parser.add_argument('--expected-run-url', required=True)
    args = parser.parse_args()
    validate_source(args.source_root)
    validate_report(lambda name: (args.artifact_dir / name).read_bytes(), args.expected_sha, args.expected_run_url)
    print('需求驗收通過：來源命名／入口、真實測試產物、證據連結與 base 徽章；實機與人工視覺驗收未冒稱完成。')


if __name__ == '__main__':
    try:
        main()
    except (ContractError, KeyError, ValueError, ET.ParseError) as error:
        print('需求驗收失敗：' + str(error), file=sys.stderr)
        sys.exit(1)
