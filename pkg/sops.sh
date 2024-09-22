SOPS="$(type -p sops)"

function sops {
    test -f "$SOPS" || die "sops not found" 'e.g. binenv install sops'
    test -f "$1" && {
        sops_edit "$1"
        return $?
    }
    cmd="${1:-help}"
    shift
    case "$cmd" in
    e | encrypt) sops_encrypt "$@" ;;
    *)
        echo "Usage: sops encrypt|decrypt|edit|view|exec|rotate|rekey|import|export|help"
        return 1
        ;;
    esac
}

function sops_encrypt {
    local file="${1:-n.a.}"
    test -f "$file" || die "File not found: $file" "Usage: sops <e|encrypt> <file>"
    local f && f="$(dirname "$file")"
    f="$(find "$f" -name 'sops.age.pub' -print -quit)"
    if [ ! -f "$f" ]; then die "'sops.age.pub' not found within the directory of $file or below."; fi
    shw "${SOPS:-}" --age="$(cat "$f")" --encrypt --encrypted-regex '^(data|stringData)$' --in-place "${file:-}"
}
