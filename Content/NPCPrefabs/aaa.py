import xml.etree.ElementTree as ET
import os

# --- 配置 ---
# !! 确保这里的文件名是你要处理的文件 !!
xml_filename = 'SpecialNpcs.txt'

# 指定输出文件名（如果想保存到文件而不是只打印）
output_filename = 'npc_spawn_commands.txt'
# output_filename = None # 取消这行的注释可以只打印到控制台

# -------------

def generate_spawn_commands(input_file):
    """
    解析指定的 XML 文件并生成 spawnnpc 指令列表。

    Args:
        input_file (str): 输入的 XML 文件路径。

    Returns:
        list: 包含生成指令的字符串列表。
              如果文件不存在或解析失败则返回空列表。
    """
    commands = []
    if not os.path.exists(input_file):
        print(f"错误：输入文件 '{input_file}' 不存在。")
        return commands

    try:
        print(f"正在读取文件: {input_file}")
        # 解析 XML 文件，显式使用 UTF-8 编码
        tree = ET.parse(input_file, parser=ET.XMLParser(encoding='utf-8'))
        root = tree.getroot() # 根元素

        # !! 修改在这里: 使用 './/npcset' 查找所有层级的 npcset 标签 !!
        # 这样可以处理 <npcsets><Override><npcset>...</npcset></Override></npcsets> 结构
        print("正在查找 './/npcset'...") # 添加调试信息
        npcset_elements = root.findall('.//npcset')
        print(f"找到 {len(npcset_elements)} 个 <npcset> 元素。") # 添加调试信息

        for npcset_element in npcset_elements:
            npcset_id = npcset_element.get('identifier')
            if not npcset_id:
                print(f"警告：找到一个没有 'identifier' 的 <npcset> 标签，已跳过。")
                continue # 跳过没有 identifier 的 npcset

            # 遍历当前 <npcset> 下的所有 <npc> 标签
            npc_elements = npcset_element.findall('npc')
            # print(f"  在 '{npcset_id}' 中查找 <npc>... 找到 {len(npc_elements)} 个。") # 添加调试信息

            for npc_element in npc_elements:
                npc_id = npc_element.get('identifier')
                if not npc_id:
                    print(f"警告：在 npcset '{npcset_id}' 中找到一个没有 'identifier' 的 <npc> 标签，已跳过。")
                    continue # 跳过没有 identifier 的 npc

                # 构建指令字符串
                command = f"spawnnpc {npcset_id} {npc_id}"
                commands.append(command)

        print(f"文件处理完成，共找到 {len(commands)} 条有效指令。") # 修改了最终输出信息

    except ET.ParseError as e:
        print(f"解析 XML 文件 '{input_file}' 时出错: {e}")
    except Exception as e:
        print(f"处理文件 '{input_file}' 时发生未知错误: {e}")

    return commands

# --- 主程序执行 ---
if __name__ == "__main__":
    generated_commands = generate_spawn_commands(xml_filename)

    if generated_commands:
        if output_filename:
            try:
                with open(output_filename, 'w', encoding='utf-8') as f:
                    for cmd in generated_commands:
                        f.write(cmd + ' cursor\n') # 每条指令占一行
                print(f"指令已成功保存到文件: '{output_filename}'")
            except IOError as e:
                print(f"错误：无法写入输出文件 '{output_filename}': {e}")
                # 即使写入失败，也打印到控制台
                print("\n--- 生成的 Spawn 指令 ---")
                for cmd in generated_commands:
                    print(cmd)
        else:
            # 如果没有指定输出文件，直接打印到控制台
            print("\n--- 生成的 Spawn 指令 ---")
            for cmd in generated_commands:
                print(cmd)
    else:
        print("未能生成任何指令。请检查 XML 文件结构和脚本逻辑。")