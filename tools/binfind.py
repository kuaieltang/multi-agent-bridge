"""在大文件里按正则搜索，可选要求命中附近同时出现某个关键词。

用法:
    python binfind.py <文件> <正则> [附近必须出现的关键词] [最多打印条数]

用于反查 Agent 读取「用户级规则/记忆文件」时用的真实路径与文件名。
"""
import re
import sys

CONTEXT = 160


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    path = sys.argv[1]
    pattern = sys.argv[2]
    near = sys.argv[3] if len(sys.argv) > 3 else None
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 12

    with open(path, 'rb') as f:
        data = f.read()
    text = data.decode('utf-8', 'replace')

    rx = re.compile(pattern)
    shown = 0
    total = 0
    for m in rx.finditer(text):
        total += 1
        lo = max(0, m.start() - CONTEXT)
        hi = min(len(text), m.end() + CONTEXT)
        snippet = text[lo:hi].replace('\r', ' ').replace('\n', ' ')
        if near and near not in snippet:
            continue
        print(f'\n@{m.start()}: ...{snippet}...')
        shown += 1
        if shown >= limit:
            break
    print(f'\n[共 {total} 处命中，筛选后打印 {shown} 处]')
    return 0


if __name__ == '__main__':
    sys.exit(main())
