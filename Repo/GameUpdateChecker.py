import os
import subprocess
import sys
import re
import shutil
from typing import Set, Dict, Tuple, List, Optional
import xml.etree.ElementTree as stdlib_et

try:
    from lxml import etree
except ImportError:
    etree = None

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# 导入您提供的现有脚本中的函数, 以便重用逻辑
# 假设 update_checker.py, release.py 和 item_list_generator.py 都在同一个 Repo 文件夹中
# 使用 conda Baro_dev 环境运行
try:
    import item_list_generator
except ImportError:
    print("错误: 无法导入 'item_list_generator.py'.")
    print("请确保 'update_checker.py' 和 'item_list_generator.py' 在同一个文件夹中.")
    sys.exit(1)

# --- 路径配置 ---

def _get_paths() -> Tuple[str, str, str, str]:
    """确定并返回所有必要的路径."""
    repo_dir = os.path.dirname(os.path.abspath(__file__))
    mod_root_dir = os.path.abspath(os.path.join(repo_dir, '..'))
    vanilla_content_dir = os.path.abspath(os.path.join(mod_root_dir, '..', '..', '..', 'Barotrauma', 'Content'))
    output_file_path = os.path.join(mod_root_dir, 'Items_NeedUpdate.md')
    
    return repo_dir, mod_root_dir, vanilla_content_dir, output_file_path

# --- 核心功能 ---

EXCLUDED_ITEM_ANCESTORS = {
    'Fabricate',
    'Deconstruct',
    'Inventory',
    'ItemSet',
    'npcsets',
    'Jobs',
    'Missions',
}


def _run_git(args: List[str], cwd: str, check: bool = True) -> subprocess.CompletedProcess:
    """Run a git command and return the completed process."""
    return subprocess.run(
        ['git'] + args,
        cwd=cwd,
        capture_output=True,
        check=check,
    )


def _get_changed_xml_files(vanilla_content_path: str) -> List[Tuple[str, str, str]]:
    """
    Return changed XML files as (status, old_path, new_path).
    Renames/copies include both old and new paths; other statuses use the same path twice.
    """
    result = _run_git(['diff-tree', '--no-commit-id', '--name-status', '-r', 'HEAD'], vanilla_content_path)
    changed_files = []

    for raw_line in result.stdout.decode('utf-8', errors='replace').splitlines():
        if not raw_line.strip():
            continue

        parts = raw_line.split('\t')
        status = parts[0]

        if (status.startswith('R') or status.startswith('C')) and len(parts) >= 3:
            old_path, new_path = parts[1], parts[2]
        elif len(parts) >= 2:
            old_path = new_path = parts[1]
        else:
            continue

        if old_path.endswith('.xml') or new_path.endswith('.xml'):
            changed_files.append((status, old_path, new_path))

    return changed_files


def _read_git_file(vanilla_content_path: str, revision: str, file_path_rel: str) -> Optional[bytes]:
    """Read a file from a git revision. Returns None when the file does not exist there."""
    result = _run_git(['show', f'{revision}:{file_path_rel}'], vanilla_content_path, check=False)
    if result.returncode != 0:
        return None
    return result.stdout


def _read_worktree_file(file_path_abs: str) -> Optional[bytes]:
    if not os.path.exists(file_path_abs):
        return None

    with open(file_path_abs, 'rb') as file:
        return file.read()


def _extract_item_snapshots(xml_content: Optional[bytes]) -> Dict[str, bytes]:
    """
    Extract comparable XML snapshots for real item definitions, keyed by identifier.
    Whitespace-only formatting differences are ignored by remove_blank_text + c14n.
    """
    if not xml_content:
        return {}

    if etree is not None:
        return _extract_item_snapshots_lxml(xml_content)

    return _extract_item_snapshots_stdlib(xml_content)


def _extract_item_snapshots_lxml(xml_content: bytes) -> Dict[str, bytes]:
    parser = etree.XMLParser(recover=True, remove_blank_text=True, remove_comments=True, encoding='utf-8')
    root = etree.fromstring(xml_content, parser=parser)
    if root is None:
        return {}

    items = _find_item_nodes(root)
    return _build_lxml_snapshots(items)


def _extract_item_snapshots_stdlib(xml_content: bytes) -> Dict[str, bytes]:
    root = stdlib_et.fromstring(xml_content)
    items = _find_item_nodes(root)
    return _build_stdlib_snapshots(items)


def _local_tag(tag: str) -> str:
    return tag.rsplit('}', 1)[-1]


def _find_item_nodes(root) -> List:
    items = []

    def walk(node, has_excluded_ancestor: bool):
        tag = _local_tag(node.tag)
        if tag == 'Item' and node.get('identifier') and not has_excluded_ancestor:
            items.append(node)

        child_has_excluded_ancestor = has_excluded_ancestor or tag in EXCLUDED_ITEM_ANCESTORS
        for child in list(node):
            walk(child, child_has_excluded_ancestor)

    walk(root, False)
    return items


def _build_lxml_snapshots(items: List) -> Dict[str, bytes]:
    snapshots = {}
    for item in items:
        item_id = item.get('identifier')
        if not item_id:
            continue

        item_snapshot = etree.tostring(item, method='c14n', with_comments=False)
        snapshots.setdefault(item_id, []).append(item_snapshot)

    return {
        item_id: b'\n'.join(sorted(item_snapshots))
        for item_id, item_snapshots in snapshots.items()
    }


def _build_stdlib_snapshots(items: List) -> Dict[str, bytes]:
    snapshots = {}
    for item in items:
        item_id = item.get('identifier')
        if not item_id:
            continue

        _normalize_stdlib_element(item)
        item_snapshot = stdlib_et.tostring(item, encoding='utf-8', short_empty_elements=True)
        snapshots.setdefault(item_id, []).append(item_snapshot)

    return {
        item_id: b'\n'.join(sorted(item_snapshots))
        for item_id, item_snapshots in snapshots.items()
    }


def _normalize_stdlib_element(element) -> None:
    element.attrib = dict(sorted(element.attrib.items()))

    if element.text is not None and not element.text.strip():
        element.text = None
    if element.tail is not None and not element.tail.strip():
        element.tail = None

    for child in list(element):
        _normalize_stdlib_element(child)


def _get_changed_item_ids(old_items: Dict[str, bytes], new_items: Dict[str, bytes]) -> Set[str]:
    """Return item identifiers whose XML changed between old and new snapshots."""
    changed_item_ids = set()
    for item_id in set(old_items).union(new_items):
        if old_items.get(item_id) != new_items.get(item_id):
            changed_item_ids.add(item_id)
    return changed_item_ids


def get_updated_vanilla_items(vanilla_content_path: str) -> Tuple[Set[str], Dict[str, str]]:
    """
    使用 git 获取上一次 commit 中修改的 XML 文件, 并提取其中真正变更的 item identifiers.
    返回一个包含所有 item ID 的集合, 以及一个 ID到其文件路径的映射.
    """
    print(f"\n1. 正在检查 '{vanilla_content_path}' 的 git 历史记录...")
    if not os.path.isdir(os.path.join(vanilla_content_path, '.git')):
        print(f"错误: '{vanilla_content_path}' 不是一个 git 仓库. 无法检测更新.")
        sys.exit(1)

    try:
        xml_files = _get_changed_xml_files(vanilla_content_path)
    except FileNotFoundError:
        print("错误: 'git' 命令未找到. 请确保 Git 已经安装并且在系统的 PATH 中.")
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        stderr = e.stderr.decode('utf-8', errors='replace') if e.stderr else ''
        print(f"错误: 执行 git 命令失败. \n{stderr}")
        sys.exit(1)

    updated_item_ids = set()
    item_path_map = {}
    
    if not xml_files:
        print("在上一次 git commit 中没有找到被修改的 .xml 文件.")
        return updated_item_ids, item_path_map

    print(f"发现在上一次 commit 中有 {len(xml_files)} 个 .xml 文件被修改:")
    for status, old_path_rel, new_path_rel in xml_files:
        display_path = new_path_rel if not status.startswith('D') else old_path_rel
        
        # 排除 Items/Assemblies 目录，因为它们保存的是物品组合而不是单独物品的定义
        if display_path.replace('\\', '/').startswith('Items/Assemblies/'):
            continue

        print(f"  - {display_path}")
        
        try:
            old_xml = None if status.startswith('A') else _read_git_file(vanilla_content_path, 'HEAD^', old_path_rel)
            new_xml = None if status.startswith('D') else _read_worktree_file(os.path.join(vanilla_content_path, new_path_rel))

            old_items = _extract_item_snapshots(old_xml)
            new_items = _extract_item_snapshots(new_xml)
            identifiers = _get_changed_item_ids(old_items, new_items)

            if identifiers:
                updated_item_ids.update(identifiers)
                report_path = new_path_rel if not status.startswith('D') else old_path_rel
                for item_id in identifiers:
                    item_path_map[item_id] = report_path.replace('\\', '/')
        except Exception as e:
            print(f"处理文件 '{display_path}' 时出错: {e}")
            
    print(f"从更新的香草文件中提取了 {len(updated_item_ids)} 个真正变更的唯一 item ID.")
    return updated_item_ids, item_path_map


def get_mod_overridden_items(mod_root_path: str) -> Set[str]:
    """
    解析 itemlist.md 文件来获取被模组覆盖的物品ID列表.
    """
    print("\n2. 正在解析模组覆盖的物品列表...")
    item_list_md_path = os.path.join(mod_root_path, 'About', 'itemlist.md')
    
    if not os.path.exists(item_list_md_path):
        print(f"警告: '{item_list_md_path}' 未找到.")
        print("将首先尝试生成该文件...")
        try:
            subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'item_list_generator.py')], check=True)
        except Exception as e:
            print(f"错误: 自动生成 'itemlist.md' 失败: {e}. 请手动运行 item_list_generator.py 后再试.")
            sys.exit(1)
        
        if not os.path.exists(item_list_md_path):
            print("错误: 自动生成 'itemlist.md' 失败. 请手动运行 item_list_generator.py 后再试.")
            sys.exit(1)
        print("'itemlist.md' 已成功生成.")

    overridden_ids = set()
    try:
        with open(item_list_md_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        in_overridden_section = False
        for line in lines:
            if "## Items Overridden by This Mod" in line:
                in_overridden_section = True
                continue
            if "## Items Added by This Mod" in line:
                in_overridden_section = False
                break
            
            if in_overridden_section:
                match = re.match(r'\|\s*([^|]+?)\s*\|', line)
                if match:
                    item_id = match.group(1).strip()
                    if item_id and item_id not in ["ID", ":---"]:
                        overridden_ids.add(item_id)
    except Exception as e:
        print(f"读取或解析 '{item_list_md_path}' 时出错: {e}")
        return set()

    print(f"从 'itemlist.md' 中找到 {len(overridden_ids)} 个被模组覆盖的 item ID.")
    return overridden_ids


def write_report(items_to_update: Set[str], translations: Tuple[Dict, Dict], item_path_map: Dict, output_path: str, vanilla_content_dir: str):
    """
    将需要更新的物品列表写入指定的 Markdown 文件.
    此版本按路径排序, 并生成从 MD 文件到目标文件的相对路径.
    输出的 path 应为 [文件名](相对路径)
    """
    print("\n4. 正在生成更新报告...")
    chinese_translations, english_translations = translations

    # 准备用于排序的数据结构: [(path, item_id), ...]
    report_data = []
    for item_id in items_to_update:
        path = item_path_map.get(item_id, "Unknown Path")
        report_data.append((path, item_id))

    # 主要按路径排序, 其次按 ID 排序
    report_data.sort()

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("# Potentially Outdated Items Report\n\n")
        f.write("此报告列出了最近香草更新中被修改, **并且**也同时被本模组覆盖的物品.\n")
        f.write("这些物品可能需要检查和更新以兼容最新版本.\n\n")
        
        f.write("| ID | English | Chinese | Vanilla File Path |\n")
        f.write("|:---|:---|:---|:---|\n")

        if not report_data:
            f.write("| (没有找到需要更新的重叠物品) | | | |\n")
        else:
            # 获取报告文件所在的目录
            report_dir = os.path.dirname(output_path)
            
            for path, item_id in report_data:
                en_name = english_translations.get(item_id, "N/A")
                cn_name = chinese_translations.get(item_id, "N/A")
                
                # 计算从报告文件到目标文件的相对路径
                target_file_abs_path = os.path.join(vanilla_content_dir, path)
                relative_path = os.path.relpath(target_file_abs_path, report_dir)
                # 将路径中的反斜杠替换为正斜杠, 以确保是有效的 URL 格式
                link_path = relative_path.replace('\\', '/')
                
                # 取文件名
                file_name = os.path.basename(path) if path != "Unknown Path" else "Unknown Path"
                # 创建 Markdown 链接: [文件名](相对路径)
                path_link = f"[{file_name}]({link_path})"
                
                f.write(f"| {item_id} | {en_name} | {cn_name} | {path_link} |\n")

    print(f"报告已成功写入到: {output_path}")

def cleanup_pycache():
    """删除当前目录及其子目录中的所有 __pycache__ 文件夹."""
    repo_dir = os.path.dirname(os.path.abspath(__file__))
    print(f"\n正在清理 {repo_dir} 中的 __pycache__ 目录...")
    
    removed_count = 0
    for root, dirs, files in os.walk(repo_dir):
        if '__pycache__' in dirs:
            pycache_path = os.path.join(root, '__pycache__')
            try:
                shutil.rmtree(pycache_path)
                removed_count += 1
                print(f"已删除: {pycache_path}")
            except Exception as e:
                print(f"删除 {pycache_path} 时出错: {e}")
    
    if removed_count > 0:
        print(f"清理完成，共删除了 {removed_count} 个 __pycache__ 目录")
    else:
        print("未找到需要清理的 __pycache__ 目录")

# --- 主程序 ---

def main():
    """主业务流程编排."""
    try:
        print("--- 开始检查模组与香草更新的重叠项 ---")
        repo_dir, mod_root_dir, vanilla_content_dir, output_file_path = _get_paths()

        print(f"Mod 根目录: {mod_root_dir}")
        print(f"香草 Content 目录: {vanilla_content_dir}")
        print(f"输出文件: {output_file_path}")

        # 步骤 1: 获取香草更新中的物品
        updated_vanilla_ids, item_path_map = get_updated_vanilla_items(vanilla_content_dir)
        if not updated_vanilla_ids:
            print("\n没有从香草更新中找到任何物品, 进程结束.")
            write_report(set(), ({}, {}), {}, output_file_path, vanilla_content_dir)
            return

        # 步骤 2: 获取模组覆盖的物品
        mod_overridden_ids = get_mod_overridden_items(mod_root_dir)

        # 步骤 3: 找出交集
        items_that_need_update = updated_vanilla_ids.intersection(mod_overridden_ids)
        print(f"\n3. 比较完成: 发现 {len(items_that_need_update)} 个物品需要检查.")

        # 步骤 4: 获取翻译以便报告内容更友好
        print("正在收集翻译...")
        chinese_translations, english_translations = item_list_generator.get_all_translations(mod_root_dir, vanilla_content_dir)
        print(f"收集了 {len(chinese_translations)} 条中文翻译和 {len(english_translations)} 条英文翻译.")

        # 步骤 5: 生成并写入报告 (注意: 额外传递了 vanilla_content_dir)
        write_report(items_that_need_update, (chinese_translations, english_translations), item_path_map, output_file_path, vanilla_content_dir)
        
        print("\n--- 检查完成 ---")
    finally:
        # 程序结束时清理 __pycache__
        cleanup_pycache()


if __name__ == "__main__":
    repo_directory = os.path.dirname(os.path.abspath(__file__))
    os.chdir(repo_directory)
    main()
