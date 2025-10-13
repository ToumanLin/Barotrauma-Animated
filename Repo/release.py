import os
import shutil
import sys
import io
import subprocess
import re

# --- Configuration Constants ---
# Default path for Barotrauma's vanilla content.
BAROTRAUMA_CONTENT_PATH = r'C:\Program Files (x86)\Steam\steamapps\common\Barotrauma\Content'

# --- Utility Functions ---

def _get_script_and_mod_paths() -> tuple[str, str, str]:
    """
    Determines and returns the current script's directory (Repo),
    the mod's root directory, and the release output directory.
    """
    current_repo_dir = os.path.dirname(os.path.abspath(__file__))
    mod_root_dir = os.path.abspath(os.path.join(current_repo_dir, '..'))
    release_output_dir = os.getcwd()
    return current_repo_dir, mod_root_dir, release_output_dir

def _get_current_modversion(mod_root_dir: str) -> str:
    """
    Reads the current modversion from the changelog.txt file (line 5).
    """
    changelog_path = os.path.join(mod_root_dir, 'About', 'changelog.txt')
    if not os.path.exists(changelog_path):
        print(f"Warning: changelog.txt not found at {changelog_path}")
        return "1.0.0"
    
    try:
        with io.open(changelog_path, 'r', encoding='utf-8-sig') as f:
            lines = f.readlines()
        
        # Get version from line 5 (index 4)
        if len(lines) >= 5:
            current_version = lines[4].strip()
            # Basic validation for version format
            if re.match(r'^\d+\.\d+\.\d+$', current_version):
                return current_version
            else:
                print(f"Warning: Invalid version format in changelog.txt line 5: {current_version}")
                return "1.0.0"
        else:
            print("Warning: changelog.txt has fewer than 5 lines")
            return "1.0.0"
    except Exception as e:
        print(f"Error reading changelog.txt: {e}")
        return "1.0.0"

def _prompt_for_new_version(current_version: str) -> str:
    """
    Prompts the user to input a new version number.
    If user just presses Enter, uses the current version.
    """
    print(f"\nCurrent modversion: {current_version}")
    while True:
        new_version = input("Enter new modversion ([Main Version].[Sub Version].[Update Count]) or press Enter to keep current: ").strip()
        if not new_version:
            # User just pressed Enter, use current version
            print(f"Using current version: {current_version}")
            return current_version
        else:
            # Basic validation for version format (x.y.z)
            if re.match(r'^\d+\.\d+\.\d+$', new_version):
                return new_version
            else:
                print("Invalid version format. Please use format: x.y.z (e.g., 2.0.2)")

def _perform_safety_checks(mod_root_dir: str, release_output_dir: str):
    """
    Performs critical safety checks before proceeding with the release process.
    Exits if any forbidden conditions are met.
    """
    print("Performing safety checks...")
    if os.path.normcase(release_output_dir) == os.path.normcase(os.path.join(os.environ.get('WINDIR', ''), 'System32')):
        print("ERROR: Running in System32 is forbidden! Aborting.")
        sys.exit(1)
    
    if os.path.normcase(release_output_dir) == os.path.normcase(mod_root_dir):
        print("ERROR: This script should NOT be run directly from the mod's source directory.")
        print("Please run it from your intended release output directory (e.g., an empty folder). Aborting.")
        sys.exit(1)
    print("Safety checks passed.")

def _clean_directory(directory_path: str, exclude_file: str = None):
    """
    Cleans all files and subdirectories within the given directory.
    Optionally excludes a specific file from deletion.
    """
    print(f"Cleaning directory: {directory_path}...")
    try:
        for item in os.listdir(directory_path):
            item_path = os.path.join(directory_path, item)
            if exclude_file and os.path.normcase(item_path) == os.path.normcase(os.path.abspath(exclude_file)):
                continue
            if os.path.isfile(item_path):
                os.remove(item_path)
            elif os.path.isdir(item_path):
                shutil.rmtree(item_path)
        print("Directory cleaned successfully.")
    except Exception as e:
        print(f"Error cleaning directory {directory_path}: {e}")
        sys.exit(1)

def _copy_files_and_folders(source_root: str, destination_root: str, folders_to_copy: list[str], files_to_copy: list[str]):
    """
    Copies specified folders and files from a source to a destination directory.
    """
    print("\nCopying folders...")
    for folder in folders_to_copy:
        src_folder = os.path.join(source_root, folder)
        dest_folder = os.path.join(destination_root, folder)
        try:
            if os.path.exists(src_folder):
                if os.path.exists(dest_folder):
                    shutil.rmtree(dest_folder) # Remove existing to avoid errors with copytree
                shutil.copytree(src_folder, dest_folder)
                print(f"Copied folder: '{folder}'")
            else:
                print(f"Warning: Source folder '{src_folder}' not found. Skipping.")
        except Exception as e:
            print(f"Error copying folder '{folder}': {e}")
            sys.exit(1)
    
    print("\nCopying files...")
    for file_name in files_to_copy:
        src_file = os.path.join(source_root, file_name)
        dest_file = os.path.join(destination_root, file_name)
        try:
            if os.path.exists(src_file):
                shutil.copy2(src_file, dest_file) # copy2 preserves metadata
                print(f"Copied file: '{file_name}'")
            else:
                print(f"Error: Source file '{src_file}' not found. Aborting.")
                sys.exit(1)
        except Exception as e:
            print(f"Error copying file '{file_name}': {e}")
            sys.exit(1)

def _copy_release_batch_file(source_repo_dir: str, destination_release_dir: str):
    """
    Copies the ZZ_Release.bat file from the Repo directory to the 00_RELEASE directory.
    """
    print("\nCopying ZZ_Release.bat to output directory...")
    src_batch_file = os.path.join(source_repo_dir, 'ZZ_Release.bat')
    dest_batch_file = os.path.join(destination_release_dir, 'ZZ_Release.bat')
    try:
        if os.path.exists(src_batch_file):
            shutil.copy2(src_batch_file, dest_batch_file)
            print(f"Copied 'ZZ_Release.bat' to '{dest_batch_file}'")
        else:
            print(f"Warning: 'ZZ_Release.bat' not found in Repo directory at '{src_batch_file}'. Skipping copy.")
    except Exception as e:
        print(f"Error copying 'ZZ_Release.bat': {e}")
        sys.exit(1)

# --- Core Release Process Steps ---

def generate_item_list(repo_dir: str, mod_root_dir: str):
    """
    Calls the item_list_generator.py script as a subprocess.
    """
    print("\nGenerating item list...")
    item_list_generator_script_path = os.path.join(repo_dir, 'item_list_generator.py')
    
    if not os.path.exists(item_list_generator_script_path):
        print(f"Error: item_list_generator.py not found at {item_list_generator_script_path}. Aborting.")
        sys.exit(1)

    try:
        # The item_list_generator.py script is designed to run standalone
        # and figures out its mod_root_dir and vanilla_path internally.
        # It also places the output in the 'About' folder within the mod_root_dir.
        subprocess.run([sys.executable, item_list_generator_script_path], check=True)
        print("Item list generation successful.")
    except subprocess.CalledProcessError as e:
        print(f"Error generating item list: {e}")
        print("Please ensure item_list_generator.py runs correctly standalone.")
        sys.exit(1)
    except FileNotFoundError:
        print(f"Error: Python interpreter '{sys.executable}' not found. Ensure Python is in your PATH.")
        sys.exit(1)

def modify_release_filelist(filelist_path: str, new_version: str) -> bool:
    """
    Modifies the filelist.xml copied to the release directory.
    This function contains the logic previously in filelist_modifier.py.
    """
    print(f"\nModifying filelist.xml at: {filelist_path}...")
    if not os.path.exists(filelist_path):
        print(f"Error: filelist.xml not found at {filelist_path}")
        return False

    try:
        with io.open(filelist_path, 'r', encoding='utf-8-sig') as f:
            content = f.read()

        # Remove ArchiveAndReference lines
        lines = content.split('\n')
        filtered_lines = [line for line in lines if "ArchiveAndReference" not in line]
        content = '\n'.join(filtered_lines)
        
        # Update the name attribute (remove -DEV and add steamworkshopid)
        old_name_attr = 'name="[EA-HI]木卫二萌化计划-DEV"'
        new_name_attr = 'name="[EA-HI]木卫二萌化计划" steamworkshopid="2809175631"'
        content = content.replace(old_name_attr, new_name_attr)
        
        # Update the modversion
        old_version_pattern = r'modversion="[^"]*"'
        new_version_attr = f'modversion="{new_version}"'
        content = re.sub(old_version_pattern, new_version_attr, content)

        with io.open(filelist_path, 'w', encoding='utf-8-sig') as f:
            f.write(content)
        print(f"Filelist.xml modified successfully. Updated version to: {new_version}")
        return True
    except Exception as e:
        print(f"Error modifying filelist.xml: {e}")
        return False

# --- Main Release Orchestration ---

def run_release_process():
    """
    Orchestrates the entire mod release preparation process by calling
    individual functions.
    """
    print("--- Starting Mod Release Preparation ---")

    repo_dir, mod_root_dir, release_output_dir = _get_script_and_mod_paths()

    print(f"Mod Source Directory: {mod_root_dir}")
    print(f"Release Output Directory: {release_output_dir}")
    input("\nPress Enter to continue or Ctrl+C to abort...")

    _perform_safety_checks(mod_root_dir, release_output_dir)

    # Clean the output directory (where the new release files will go)
    # The current script (release.py) might be in the output directory if executed directly there.
    # We must exclude the 'ZZ_Release.bat' from deletion if it exists in the output directory
    # so that the batch script isn't deleted by its own launched Python script before it finishes.
    _clean_directory(release_output_dir, exclude_file=os.path.join(release_output_dir, 'ZZ_Release.bat'))

    # Generate the item list (this script will place it in mod_root_dir/About)
    generate_item_list(repo_dir, mod_root_dir)

    # Define what to copy
    folders_to_copy = ["About", "Content", "Subs", "要中文人名就用这里面的文件替换names xml"]
    files_to_copy = ["filelist.xml"] # Copy filelist.xml before modifying it

    _copy_files_and_folders(mod_root_dir, release_output_dir, folders_to_copy, files_to_copy)

    # Modify the filelist.xml that was just copied to the release output directory
    copied_filelist_path = os.path.join(release_output_dir, 'filelist.xml')
    
    # Get current version and prompt for new version
    current_version = _get_current_modversion(mod_root_dir)
    new_version = _prompt_for_new_version(current_version)
    
    if not modify_release_filelist(copied_filelist_path, new_version):
        print("Release process aborted due to filelist modification failure.")
        sys.exit(1)

    # Copy the ZZ_Release.bat back to the output directory
    _copy_release_batch_file(repo_dir, release_output_dir)

    print("\n--- Mod Release Preparation Done. ---")
    input("Press Enter to exit...")

if __name__ == "__main__":
    run_release_process()