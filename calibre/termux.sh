#!/data/data/com.termux/files/usr/bin/sh
# SEM ROOT (Termux + proot-distro) — BETA, ainda nao testado: ponte entre o Termux e o Debian do proot.
# O calibre-server.sh roda DENTRO do Debian; este script roda no Termux e o chama.
#
# Uso: ~/calibre/termux.sh {start|stop|restart|status}
#      ~/calibre/termux.sh run COMANDO...    (roda qualquer comando dentro do Debian)

SCRIPT=/root/calibre/calibre-server.sh

deb() {
    proot-distro login debian -- "$@"
}

case "$1" in
start | restart)
    # Impede o Android de suspender o Termux com a tela apagada.
    termux-wake-lock 2>/dev/null
    # O proot fica vivo enquanto o servidor roda, por isso vai para segundo plano.
    nohup proot-distro login debian -- "$SCRIPT" "$1" >"$HOME/calibre/proot.log" 2>&1 &
    sleep 15
    deb "$SCRIPT" status
    ;;
stop | status)
    deb "$SCRIPT" "$1"
    ;;
run)
    shift
    deb "$@"
    ;;
*)
    echo "Uso: $0 {start|stop|restart|status|run COMANDO...}"
    exit 1
    ;;
esac
