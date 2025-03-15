import os
import configparser

def create_directory_structure(config, root_path):
    for section in config.sections():
        if section == "Video":
            video_path = os.path.join(root_path, "Video")  
            os.makedirs(video_path, exist_ok=True)

            for sub_section in config.sections():
                if sub_section.startswith("Video."):
                    sub_folder = sub_section.split(".")[1]  
                    subfolder_path = os.path.join(video_path, sub_folder)
                    os.makedirs(subfolder_path, exist_ok=True)

                    for option in config.options(sub_section):
                        if config.has_option(sub_section, option):  
                            subfolder_subpath = os.path.join(subfolder_path, option)
                            os.makedirs(subfolder_subpath, exist_ok=True)  

        elif section == "未整理":
            unorganized_path = os.path.join(root_path, "未整理")
            os.makedirs(unorganized_path, exist_ok=True)
            
            for option in config.options(section):
                if config.has_option(section, option):  
                    subfolder_path = os.path.join(unorganized_path, option)
                    os.makedirs(subfolder_path, exist_ok=True)

def create_directory_tree_output(config, root_path, output_file):
    output_file.write(f"├── Media\n")

    for section in config.sections():
        if section == "未整理":
            output_file.write(f"    ├── {section}\n")
            for option in config.options(section):
                if config.has_option(section, option):
                    output_file.write(f"        ├── {option}\n")
        
        elif section == "Video":
            output_file.write(f"    ├── Video\n")
            for sub_section in config.sections():
                if sub_section.startswith("Video."):
                    sub_folder = sub_section.split(".")[1]  
                    output_file.write(f"        ├── {sub_folder}\n")
                    for option in config.options(sub_section):
                        if config.has_option(sub_section, option):
                            output_file.write(f"            ├── {option}\n")

def save_tree_and_create_structure(ini_path, root_path, output_path):
    config = configparser.ConfigParser()
    config.read(ini_path, encoding='utf-8')

    create_directory_structure(config, root_path)
    
    with open(output_path, 'w', encoding='utf-8') as file:
        file.write("目录树：\n")
        create_directory_tree_output(config, root_path, file)

if __name__ == "__main__":
    ini_path = "目录配置.ini"  # 修改为你的目录配置文件路径
    root_path = "Media"  # 根目录为 Media
    output_path = "directory_tree.txt"  # 输出到当前目录下的txt文件

    save_tree_and_create_structure(ini_path, root_path, output_path)
    print(f"目录树已保存到 {output_path}，并创建了文件夹结构。")
