"""在二进制/大文件里搜字符串，用于反查 Agent 的配置入口约定。

用法:
    python bingrep.py <文件> <关键词1> [关键词2 ...]
每个关键词给出命中次数，并打印首个命中的上下文片段。
"""
import sys

CONTEXT = 120
MAX_HITS = 5


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    path = sys.argv[1]
    keys = [k.encode('utf-8') for k in sys.argv[2:]]

    with open(path, 'rb') as f:
        data = f.read()

    print(f'文件: {path}  ({len(data):,} 字节)')
    for raw in keys:
        hits = []
        start = 0
        while len(hits) < MAX_HITS:
            i = data.find(raw, start)
            if i < 0:
                break
            hits.append(i)
            start = i + 1
        total = data.count(raw)
        print(f'\n--- {raw.decode("utf-8", "replace")}  命中 {total} 次 ---')
        for i in hits:
            lo = max(0, i - CONTEXT)
            hi = min(len(data), i + len(raw) + CONTEXT)
            snippet = data[lo:hi].decode('utf-8', 'replace')
            snippet = snippet.replace('\r', ' ').replace('\n', ' ')
            print(f'  @{i}: ...{snippet}...')
    return 0


if __name__ == '__main__':
    sys.exit(main())
