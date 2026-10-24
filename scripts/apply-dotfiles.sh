#!/usr/bin/env bash
# apply-dotfiles.sh: install the files under home/ into $HOME.
#
# Only user files are touched; nothing outside $HOME is written and no root
# rights are needed. System files are installed separately (docs/03).
#
# Usage:
#   scripts/apply-dotfiles.sh [--dry-run] [--link]
#   scripts/apply-dotfiles.sh --restore <backup-dir> [--dry-run]
#
#   --dry-run   show what would happen, change nothing
#   --link      symlink files into $HOME instead of copying them
#               (edits in $HOME then land in this repository)
#   --restore   undo an earlier run: put back the files saved in <backup-dir>
#               and remove the files that run created
#
# Existing files that differ are moved to
#   ~/.local/state/g14-dotfiles/backup-<timestamp>/<same relative path>
# before being replaced. Identical files are skipped, so running the script
# again is harmless. Each run writes a MANIFEST into its backup directory.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$REPO/home"
DRY=0
LINK=0
RESTORE=""

while (($#)); do
    case "$1" in
        --dry-run) DRY=1 ;;
        --link)    LINK=1 ;;
        --restore) RESTORE=${2:?--restore needs a directory}; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[[ -n ${HOME:-} && -d $HOME ]] || { echo "HOME is not set or does not exist" >&2; exit 1; }
[[ $(id -u) -ne 0 ]] || { echo "do not run this as root" >&2; exit 1; }

run() {
    if (( DRY )); then printf '  [dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi
}

# ------------------------------------------------------------------ restore
if [[ -n $RESTORE ]]; then
    MAN="$RESTORE/MANIFEST"
    [[ -f $MAN ]] || { echo "no MANIFEST in $RESTORE" >&2; exit 1; }
    while IFS=$'\t' read -r action rel; do
        [[ -z $rel || $rel == /* || $rel == *..* ]] && continue
        dest="$HOME/$rel"
        case "$action" in
            replaced)
                echo "restore  ~/$rel"
                run rm -f "$dest"
                run mkdir -p "$(dirname "$dest")"
                run cp -a "$RESTORE/files/$rel" "$dest" ;;
            created)
                echo "remove   ~/$rel"
                run rm -f "$dest" ;;
        esac
    done < "$MAN"
    echo "Restore finished. Run 'systemctl --user daemon-reload' and log out/in."
    exit 0
fi

# ------------------------------------------------------------------ install
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${XDG_STATE_HOME:-$HOME/.local/state}/g14-dotfiles/backup-$STAMP"
MAN="$BACKUP/MANIFEST"
changed=0

record() {   # record <action> <relative path>
    (( DRY )) && return 0
    mkdir -p "$BACKUP"
    printf '%s\t%s\n' "$1" "$2" >> "$MAN"
}

while IFS= read -r -d '' src; do
    rel=${src#"$SRC"/}
    dest="$HOME/$rel"

    # Already in place?
    if (( LINK )); then
        if [[ -L $dest && $(readlink "$dest") == "$src" ]]; then continue; fi
    elif [[ -f $dest && ! -L $dest ]] && cmp -s "$src" "$dest"; then
        continue
    fi

    if [[ -e $dest || -L $dest ]]; then
        echo "replace  ~/$rel  (old copy -> backup)"
        run mkdir -p "$BACKUP/files/$(dirname "$rel")"
        run mv "$dest" "$BACKUP/files/$rel"
        record replaced "$rel"
    else
        echo "create   ~/$rel"
        record created "$rel"
    fi

    run mkdir -p "$(dirname "$dest")"
    if (( LINK )); then
        run ln -s "$src" "$dest"
    else
        run cp -p "$src" "$dest"
    fi
    changed=$((changed + 1))
done < <(find "$SRC" \( -type f -o -type l \) -print0 | sort -z)

echo
if (( changed == 0 )); then
    echo "Nothing to do: everything is already in place."
    exit 0
fi
if (( DRY )); then
    echo "$changed file(s) would change. Dry run: nothing was written."
else
    echo "$changed file(s) installed. Backup and MANIFEST: $BACKUP"
    echo "Undo with: $0 --restore $BACKUP"
fi
cat <<'EOF'

Next steps (not done automatically):
  systemctl --user daemon-reload
  systemctl --user enable --now alc285-port-watch.service   # G14 speaker fix
  systemctl --user enable --now stuck-watch.timer           # optional, see docs/03
  kbuildsycoca6                                             # pick up new .desktop files
  scripts/apply-kde-settings.sh [--shortcuts]               # KDE settings
Then log out and back in.
EOF
