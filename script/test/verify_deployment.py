"""匿名 HTTPS 驗收 Pages；有限重試 CDN，不能把舊提交當成功。"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import time
import xml.etree.ElementTree as ET
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen
from urllib.error import URLError
from requirements_gate import ContractError, Page, require, validate_report, validate_svg


def validate_portal(read, readme, expected_sha, expected_run, base_url):
    report = validate_report(lambda name: read('main/' + name), expected_sha, expected_run, main=True)
    root = Page(read('index.html').decode('utf-8-sig'))
    require('main/index.html' in root.visible_links, 'R01 首頁沒有本次報告入口')
    require(any(urlsplit(link).path.endswith('/blob/main/readme.md') for link in root.visible_links), 'R01 首頁沒有使用說明入口')
    require('Unknown' not in root.visible, 'R06 首頁顯示未翻譯 Unknown')
    require(('目前程式檢查通過' if report['Success'] else '目前程式檢查未通過') in root.visible, 'R02 首頁結論與本次 JSON 不一致')
    versions = json.loads(read('versions.json').decode('utf-8-sig'))
    for version in versions:
        require(re.fullmatch(r'v\d+\.\d+\.\d+(?:-rc\d+)?', version['Version']), 'R04 非法版本路徑')
        page = Page(read(version['Path']).decode('utf-8-sig'))
        require('Unknown' not in page.visible, 'R06 舊版本頁顯示未翻譯 Unknown')
        if version['Status'] == 'Unknown':
            require('未保存測試紀錄' in page.visible, 'R06 缺少舊版證據卻沒有明確說明')
    for a in versions:
        for b in versions:
            comparison = json.loads(read('comparisons/' + a['Version'] + '--' + b['Version'] + '.json').decode('utf-8-sig'))
            if a['Status'] != 'Verified' or b['Status'] != 'Verified':
                require(comparison['Status'] == 'Unknown', 'R06 無版本證據卻推論比較結果')
    sources = re.findall(r'!\[[^\]]*\]\(([^)]+)\)', readme)
    for name in ('unit', 'integration', 'system', 'coverage'):
        expected = urljoin(base_url, 'main/' + name + '.svg')
        found = [src for src in sources if src.split('?')[0] == expected]
        require(len(found) == 1, 'R05 README 徽章未指向實際公開檔：' + name)
        # Fetch the exact README query too, rather than assuming cache variants match.
        relative = found[0][len(base_url):]
        validate_svg(read(relative), report, name)
    return report


def verify_with_retry(read, readme, sha, run, base, attempts=12, delay=10, sleep=time.sleep):
    for attempt in range(1, attempts + 1):
        try:
            return validate_portal(read, readme, sha, run, base)
        except (ContractError, KeyError, ValueError, URLError, OSError, ET.ParseError) as error:
            if attempt == attempts:
                raise
            print('部署驗收尚未符合本次來源，等待 CDN 更新（第 %d/%d 次）：%s' % (attempt, attempts, type(error).__name__))
            sleep(delay)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--expected-sha', required=True)
    parser.add_argument('--expected-run-url', required=True)
    parser.add_argument('--readme', type=Path, required=True)
    args = parser.parse_args()
    base = args.base_url.rstrip('/') + '/'
    require(urlsplit(base).scheme == 'https', '僅允許 HTTPS 公開驗收')

    def read(path):
        url = urljoin(base, path)
        require(url.startswith(base), '拒絕離開本站的產物路徑')
        request = Request(url, headers={'User-Agent': 'windows-setup-requirements-gate', 'Cache-Control': 'no-cache'})
        with urlopen(request, timeout=20) as response:
            require(response.status == 200 and response.geturl().startswith(base), '公開網址回應或來源不符')
            return response.read()

    readme = args.readme.read_text(encoding='utf-8-sig')
    report = verify_with_retry(read, readme, args.expected_sha, args.expected_run_url, base)
    ci_badges = re.findall(r'https://github\.com/[^/]+/[^/]+/actions/workflows/[^/]+/badge\.svg', readme)
    require(len(ci_badges) == 1, 'R05 缺少唯一的 GitHub CI 徽章')
    with urlopen(Request(ci_badges[0], headers={'User-Agent': 'windows-setup-requirements-gate'}), timeout=20) as response:
        require(response.status == 200, 'R05 GitHub CI 徽章不可讀')
        require(ET.fromstring(response.read()).tag == '{http://www.w3.org/2000/svg}svg', 'R05 GitHub CI 徽章不是有效 SVG')
    # This workflow is still running: a pending CI badge is legitimate here.
    summary = '## 公開部署需求驗收通過\n\n- 本次 main 提交：`%s`\n- 報告執行：%s\n- 首頁、報告、JSON／JUnit／Markdown、四個徽章與歷史頁均可讀取。\n- System／E2E 未執行，Coverage 未量測；人工視覺審查不由此 job 代替。\n' % (report['Commit'], report['RunUrl'])
    print(summary)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        Path(os.environ['GITHUB_STEP_SUMMARY']).write_text(summary, encoding='utf-8')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('公開部署驗收失敗：' + str(error), file=sys.stderr)
        sys.exit(1)
