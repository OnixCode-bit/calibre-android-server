#!/bin/sh
# Inicia/para o calibre-server e o vigia da inbox num celular Android com Debian.
# Uso: ~/calibre/calibre-server.sh {start|stop|restart|status}

DIR="$HOME/calibre"
LIB="$DIR/library"
USERDB="$DIR/users.sqlite"
LOG="$DIR/server.log"
PIDFILE="$DIR/server.pid"
WATCHER="$DIR/inbox-watcher.sh"
WATCHER_PIDFILE="$DIR/inbox.pid"
PORT=8080

alive() {
    [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null
}

start() {
    if alive "$PIDFILE"; then
        echo "calibre-server ja esta rodando (PID $(cat "$PIDFILE"))"
    else
        nohup calibre-server \
            --port "$PORT" \
            --listen-on 0.0.0.0 \
            --enable-auth \
            --auth-mode basic \
            --userdb "$USERDB" \
            --max-log-size 5 \
            --log "$LOG" \
            "$LIB" >/dev/null 2>&1 &
        echo $! >"$PIDFILE"
        sleep 3
        if alive "$PIDFILE"; then
            echo "calibre-server iniciado na porta $PORT (PID $(cat "$PIDFILE"))"
        else
            echo "calibre-server falhou ao iniciar; veja $LOG"
            return 1
        fi
    fi

    if alive "$WATCHER_PIDFILE"; then
        echo "vigia da inbox ja esta rodando (PID $(cat "$WATCHER_PIDFILE"))"
    elif [ -x "$WATCHER" ]; then
        nohup "$WATCHER" >/dev/null 2>&1 &
        echo $! >"$WATCHER_PIDFILE"
        echo "vigia da inbox iniciado (PID $(cat "$WATCHER_PIDFILE"))"
    fi
}

stop() {
    for pf in "$WATCHER_PIDFILE" "$PIDFILE"; do
        if alive "$pf"; then
            kill "$(cat "$pf")"
            echo "parado: $(basename "$pf" .pid)"
        fi
        rm -f "$pf"
    done
}

status() {
    if alive "$PIDFILE"; then echo "calibre-server: rodando (PID $(cat "$PIDFILE"))"; else echo "calibre-server: parado"; fi
    if alive "$WATCHER_PIDFILE"; then echo "vigia da inbox: rodando (PID $(cat "$WATCHER_PIDFILE"))"; else echo "vigia da inbox: parado"; fi
}

case "$1" in
start) start ;;
stop) stop ;;
restart)
    stop
    sleep 2
    start
    ;;
status) status ;;
*)
    echo "Uso: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
