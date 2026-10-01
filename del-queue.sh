#!/bin/bash
#
# del-queue.sh
# Hapus email di mail queue Postfix (Carbonio CE) berdasarkan alamat pengirim.
# Dijalankan sebagai root.
#
# Contoh:
#   ./del-queue.sh -n -s spam@contoh.com            # dry-run
#   ./del-queue.sh -s spam@contoh.com               # hapus (minta konfirmasi)
#   ./del-queue.sh -y -s a@x.com -s b@y.com         # banyak pengirim, tanpa konfirmasi
#   ./del-queue.sh -D contoh.com                    # semua pengirim @contoh.com
#   ./del-queue.sh -f daftar.txt                    # pengirim dari file (1 baris 1 alamat)

set -uo pipefail

LOG_FILE="/var/log/queue-del.log"
DRY_RUN=0
ASSUME_YES=0
SENDERS=()
DOMAINS=()

usage() {
    cat <<EOF
Penggunaan: $0 [opsi]

  -s ALAMAT   Alamat pengirim yang dihapus (exact match, boleh diulang)
  -D DOMAIN   Hapus semua pengirim dari domain ini (boleh diulang)
  -f FILE     File berisi daftar alamat pengirim (satu per baris)
  -n          Dry-run: hanya tampilkan, tidak menghapus
  -y          Jangan minta konfirmasi
  -h          Bantuan

Catatan: pencocokan tidak case-sensitive. Untuk bounce gunakan -s MAILER-DAEMON.
EOF
}

while getopts ":s:D:f:nyh" opt; do
    case "$opt" in
        s) SENDERS+=("$OPTARG") ;;
        D) DOMAINS+=("${OPTARG#@}") ;;
        f)
            if [[ ! -r "$OPTARG" ]]; then
                echo "ERROR: file '$OPTARG' tidak bisa dibaca." >&2; exit 1
            fi
            while IFS= read -r line; do
                line="${line//$'\r'/}"
                [[ -z "${line// /}" || "$line" == \#* ]] && continue
                SENDERS+=("$line")
            done < "$OPTARG"
            ;;
        n) DRY_RUN=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage; exit 0 ;;
        :) echo "ERROR: opsi -$OPTARG butuh argumen." >&2; usage; exit 1 ;;
        \?) echo "ERROR: opsi -$OPTARG tidak dikenal." >&2; usage; exit 1 ;;
    esac
done

# --- Validasi dasar ---------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: script ini harus dijalankan sebagai root." >&2
    exit 1
fi

if [[ ${#SENDERS[@]} -eq 0 && ${#DOMAINS[@]} -eq 0 ]]; then
    echo "ERROR: tentukan minimal satu pengirim (-s), domain (-D), atau file (-f)." >&2
    usage
    exit 1
fi

# --- Cari binary Postfix milik Carbonio -------------------------------------
PF_BIN=""
for d in /opt/zextras/common/sbin /opt/zextras/postfix/sbin /usr/sbin; do
    if [[ -x "$d/postqueue" && -x "$d/postsuper" ]]; then
        PF_BIN="$d"
        break
    fi
done

if [[ -z "$PF_BIN" ]]; then
    echo "ERROR: postqueue/postsuper tidak ditemukan." >&2
    exit 1
fi

POSTQUEUE="$PF_BIN/postqueue"
POSTSUPER="$PF_BIN/postsuper"

# --- Ambil queue ID yang cocok ----------------------------------------------
TMP_IDS="$(mktemp /tmp/queue-ids.XXXXXX)"
TMP_LIST="$(mktemp /tmp/queue-list.XXXXXX)"
trap 'rm -f "$TMP_IDS" "$TMP_LIST"' EXIT

SENDER_CSV="$(IFS=,; echo "${SENDERS[*]:-}")"
DOMAIN_CSV="$(IFS=,; echo "${DOMAINS[*]:-}")"

# postqueue -p: baris pertama header; tiap entri dipisah baris kosong.
# Field: $1=queue ID (akhiran * = active, ! = hold), $7=pengirim.
"$POSTQUEUE" -p 2>/dev/null | tail -n +2 | awk -v RS= \
    -v senders="$SENDER_CSV" -v domains="$DOMAIN_CSV" '
BEGIN {
    n = split(tolower(senders), a, ",")
    for (i = 1; i <= n; i++) if (a[i] != "") S[a[i]] = 1
    m = split(tolower(domains), b, ",")
    for (i = 1; i <= m; i++) if (b[i] != "") D[b[i]] = 1
}
{
    id = $1
    sender = tolower($7)
    if (id !~ /^[0-9A-Za-z]+[*!]?$/) next
    sub(/[*!]$/, "", id)

    match_ok = 0
    if (sender in S) match_ok = 1
    else {
        at = index(sender, "@")
        if (at > 0 && (substr(sender, at + 1) in D)) match_ok = 1
    }
    if (match_ok) print id "\t" sender
}' > "$TMP_LIST"

cut -f1 "$TMP_LIST" > "$TMP_IDS"
TOTAL=$(wc -l < "$TMP_IDS")

if [[ "$TOTAL" -eq 0 ]]; then
    echo "Tidak ada email di queue yang cocok."
    exit 0
fi

echo "Ditemukan $TOTAL email di queue yang cocok:"
echo "---------------------------------------------"
cut -f2 "$TMP_LIST" | sort | uniq -c | sort -rn
echo "---------------------------------------------"

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY-RUN] Tidak ada yang dihapus. Queue ID:"
    cut -f1 "$TMP_LIST" | head -n 50
    [[ "$TOTAL" -gt 50 ]] && echo "... (${TOTAL} total, hanya 50 pertama ditampilkan)"
    exit 0
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Hapus $TOTAL email ini? [y/N] " ans
    if [[ ! "$ans" =~ ^[yY]$ ]]; then
        echo "Dibatalkan."
        exit 0
    fi
fi

# --- Eksekusi hapus ---------------------------------------------------------
{
    echo "[$(date '+%F %T')] user=$(logname 2>/dev/null || echo root) hapus $TOTAL email"
    echo "[$(date '+%F %T')] pengirim: ${SENDER_CSV:-"-"} | domain: ${DOMAIN_CSV:-"-"}"
} >> "$LOG_FILE"

"$POSTSUPER" -d - < "$TMP_IDS"
RC=$?

echo "[$(date '+%F %T')] postsuper exit code: $RC" >> "$LOG_FILE"

if [[ $RC -ne 0 ]]; then
    echo "PERINGATAN: postsuper selesai dengan kode $RC. Cek $LOG_FILE dan /var/log/zimbra.log (atau mail.log)." >&2
    exit $RC
fi

echo "Selesai. Sisa queue:"
"$POSTQUEUE" -p 2>/dev/null | tail -n 1
