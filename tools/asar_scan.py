"""最小 asar 扫描器：列出路径含 skill 的条目，并可提取指定文件内容。"""
import json
import struct
import sys

ASAR = r'C:\Users\TANG\AppData\Local\Programs\DeepSeek Harness\resources\app.asar'


def load_header(path):
    with open(path, 'rb') as f:
        head = f.read(16)
        size_payload = struct.unpack('<I', head[0:4])[0]     # size pickle 的 payload 大小
        header_buf_size = struct.unpack('<I', head[4:8])[0]  # 头部缓冲区大小
        f.seek(8)
        header_buf = f.read(header_buf_size)
        # 头部缓冲区自身也是一个 Pickle：[uint32 字符串长度][JSON 字符串][padding]
        str_len = struct.unpack('<I', header_buf[0:4])[0]
        header = json.loads(header_buf[8:8 + str_len].decode('utf-8', 'replace'))
        base = 8 + header_buf_size
    return header, base, header_buf_size, size_payload


def walk(node, prefix=''):
    """yield (path, entry) for files"""
    for name, child in node.get('files', {}).items():
        p = prefix + '/' + name if prefix else name
        if 'files' in child:
            yield from walk(child, p)
        else:
            yield p, child


def main():
    header, base, header_size, json_size = load_header(ASAR)
    print(f'header_size={header_size} json_size={json_size} base={base}')
    files = list(walk(header))
    print(f'条目总数: {len(files)}')

    print('\n=== 顶层目录 ===')
    print(', '.join(sorted(header.get('files', {}).keys())))

    matches = [(p, e) for p, e in files if 'skill' in p.lower()]
    print(f'\n=== 路径含 skill 的条目: {len(matches)} 个 ===')
    for p, e in matches[:200]:
        print(f'  {e.get("size", 0):>9}  {p}')

    # 提取命令行指定的文件
    if len(sys.argv) > 1:
        target = sys.argv[1].replace('\\', '/').lstrip('/')
        for p, e in files:
            if p == target or p.endswith(target):
                off = int(e['offset'])
                size = int(e['size'])
                with open(ASAR, 'rb') as f:
                    f.seek(base + off)
                    data = f.read(size)
                print(f'\n=== {p} ({size} bytes) ===')
                sys.stdout.write(data.decode('utf-8', 'replace'))
                return
        print(f'\n未找到: {target}')


if __name__ == '__main__':
    main()
