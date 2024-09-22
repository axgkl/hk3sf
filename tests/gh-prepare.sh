set -e
d="$HOME/.config/sops/age"
test -f "$d/keys.txt" || {
    mkdir -p "$d"
    echo -e "${AGE_SECRET_KEY}" >"$d/keys.txt"
}
set -x
wget -q https://github.com/devops-works/binenv/releases/download/v0.19.11/binenv_linux_amd64
chmod +x binenv
mv binenv_linux_amd64 binenv
./binenv update
./binenv install binenv
rm binenv

for tool in sops age kubectl helm; do
    which "${tool}" || binenv install "${tool}"
done
set +x
