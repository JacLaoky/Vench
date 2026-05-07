from weasyprint import HTML

# Content for the README.md in Markdown format
readme_content = """# Trading Master 云端服务器维护手册

本项目已成功部署至 Azure (Hong Kong) 云服务器。本手册记录了日常维护、程序管理及内存优化的常用指令。

---

## 1. 远程连接 (SSH)
在 Mac 终端执行：
```bash
ssh -i tradingmaster_key.pem azureuser@20.2.88.101

screen -S moomoo
# 成功后按 Ctrl+A, D 隐藏

screen -S flask
cd ~
python3 app.py
# 成功后按 Ctrl+A, D 隐藏

sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
# 设置永久生效
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab