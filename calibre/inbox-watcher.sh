#!/bin/sh
# Vigia ~/calibre/inbox e adiciona ao Calibre os livros que chegam (ex.: pelo share SMB).
# Roda em loop; quem inicia/para é o calibre-server.sh.
#
# - Espera o arquivo ficar 15 s sem mudar (cópia pela rede terminada).
# - Adiciona pelo calibre-server em execução, com o usuário de ~/calibre/inbox.auth
#   (duas linhas: usuário e senha; chmod 600). O servidor exige login até do localhost.
# - Sucesso: apaga o arquivo da inbox. Falha: move para inbox/_falhou/.
# - Duplicados (mesmo título/autor) o Calibre ignora; o arquivo também sai da inbox.

INBOX="$HOME/calibre/inbox"
FAILED="$INBOX/_falhou"
LOG="$HOME/calibre/inbox.log"
LIBRARY_URL="http://localhost:8080/#library"
AUTH="$HOME/calibre/inbox.auth"
INTERVAL=10
EXTS='epub|pdf|mobi|azw|azw3|kfx|fb2|cbz|cbr|djvu|docx|rtf|txt|lit|pdb'

mkdir -p "$INBOX" "$FAILED"

if [ ! -r "$AUTH" ]; then
    echo "$(date '+%F %T') ERRO: falta $AUTH (usuário na 1ª linha, senha na 2ª)" >>"$LOG"
    exit 1
fi
CAL_USER=$(sed -n 1p "$AUTH")

log() {
    echo "$(date '+%F %T') $*" >>"$LOG"
}

# Mantém o log pequeno (últimas 1000 linhas)
trim_log() {
    [ -f "$LOG" ] && [ "$(wc -l <"$LOG")" -gt 2000 ] && tail -n 1000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}

log "vigia iniciado (PID $$)"
while true; do
    find "$INBOX" -path "$FAILED" -prune -o -type f ! -name '.*' ! -newermt '15 seconds ago' -print |
        while IFS= read -r f; do
            name=$(basename "$f")
            ext=$(echo "${name##*.}" | tr '[:upper:]' '[:lower:]')
            if ! echo "$ext" | grep -Eqx "$EXTS"; then
                log "ignorado (formato .$ext): $name"
                mv "$f" "$FAILED/" 2>/dev/null
                continue
            fi
            if out=$(sed -n 2p "$AUTH" | calibredb --with-library "$LIBRARY_URL" \
                --username "$CAL_USER" --password '<stdin>' add "$f" 2>&1); then
                rm -f "$f"
                case "$out" in
                *"Added book ids"*) log "adicionado: $name" ;;
                *) log "duplicado, ignorado: $name" ;;
                esac
            else
                mv "$f" "$FAILED/"
                log "FALHOU: $name :: $(echo "$out" | tail -1)"
            fi
        done
    # Remove subpastas vazias (quem arrasta uma pasta inteira)
    find "$INBOX" -mindepth 1 -type d -empty ! -path "$FAILED" -delete 2>/dev/null
    trim_log
    sleep "$INTERVAL"
done
