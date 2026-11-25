#!/bin/bash
url="$1"
[ -z "$url" ] && { echo "Usage: $0 domain.com"; exit 1; }

export PATH="$PATH:$HOME/go/bin"

# ---------- টুল ইনস্টল চেক ----------
echo "[+] Checking required tools..."

# apt প্যাকেজ (nmap, golang, git)
need_apt=""
command -v nmap >/dev/null 2>&1 || need_apt="$need_apt nmap"
command -v go   >/dev/null 2>&1 || need_apt="$need_apt golang"
command -v git  >/dev/null 2>&1 || need_apt="$need_apt git"

if [ -n "$need_apt" ]; then
  echo "[+] Installing:$need_apt"
  sudo apt update && sudo apt install -y $need_apt
else
  echo "[-] nmap, go, git already installed. Skipping."
fi

# Go টুল (নাম|ইনস্টল পাথ)
tools=(
  "assetfinder|github.com/tomnomnom/assetfinder@latest"
  "httprobe|github.com/tomnomnom/httprobe@latest"
  "waybackurls|github.com/tomnomnom/waybackurls@latest"
  "subjack|github.com/haccer/subjack@latest"
)

for entry in "${tools[@]}"; do
  name="${entry%%|*}"
  path="${entry##*|}"
  if command -v "$name" >/dev/null 2>&1; then
    echo "[-] $name already installed. Skipping."
  else
    echo "[+] Installing $name..."
    go install "$path"
  fi
done

# PATH স্থায়ীভাবে যোগ (একবারই)
grep -q 'go/bin' ~/.bashrc || echo 'export PATH=$PATH:~/go/bin' >> ~/.bashrc

# ইনস্টল ব্যর্থ হলে থামবে
for t in assetfinder httprobe waybackurls subjack nmap; do
  command -v "$t" >/dev/null 2>&1 || { echo "[!] $t install failed. Stopping."; exit 1; }
done

# ---------- রিকন শুরু ----------
base="$url/recon"
mkdir -p "$base"/{scans,httprobe,potential_takeovers,wayback/params,wayback/extensions}

echo "[+] Finding subdomains with assetfinder..."
assetfinder "$url" | grep -F "$url" | sort -u > "$base/final.txt"

echo "[+] Searching for alive domains..."
httprobe -s -p https:443 < "$base/final.txt" \
  | sed 's/https\?:\/\///; s/:443$//' | sort -u > "$base/httprobe/alive.txt"

echo "[+] Checking for possible subdomain takeover..."
subjack -w "$base/final.txt" -t 100 -timeout 30 -ssl -v 3 \
  -o "$base/potential_takeovers/potential_takeovers.txt"

echo "[+] Scanning for open ports..."
nmap -iL "$base/httprobe/alive.txt" -T4 -oA "$base/scans/scanned"

echo "[+] Scraping wayback data..."
waybackurls < "$base/final.txt" | sort -u > "$base/wayback/wayback_output.txt"

echo "[+] Compiling params..."
grep '?.*=' "$base/wayback/wayback_output.txt" | cut -d '=' -f 1 | sort -u \
  | sed 's/$/=/' > "$base/wayback/params/wayback_params.txt"

echo "[+] Sorting URLs by extension..."
for ext in js html json php aspx jsp; do
  grep -iE "\.${ext}(\?|$)" "$base/wayback/wayback_output.txt" | sort -u \
    > "$base/wayback/extensions/${ext}.txt"
done

echo "[+] Done! Results are in $base"
