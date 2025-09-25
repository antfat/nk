# === Параметры запуска ===
if [ -z "$1" ]; then
    echo "❌ Укажите номер воркера (например: 01, 02, 03)"
    exit 1
fi
WORKER_SUFFIX="$1"
BASE_WORKER_NAME="r0${WORKER_SUFFIX}"

# === Константы ===
WORKDIR="$HOME/work"
WORKER_BIN="$WORKDIR/worker"
JAR_PATH="$WORKDIR/worker.jar"

# Golden-miner настройки
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.2/golden-miner-pool-prover"
LABEL="workers"
PUBKEY="3bfNk9C3iT8VFT1hjg1w8hwASXXaL1HcyKsQCR8t7H8Xnp25My2s1oYhs6XwtKk9D8Ku2fvbnAC7yx7Xfse65a1atCQJmMG62S1tkJkgzJuJpKXQUA8ELX5ifCevEcv7iHGb"
GM_THREADS_PER_GPU=8

# Worker.jar настройки
JAR_URL="https://tht.mine-n-krush.org/miners/JavaThoughtMinerStratum.zip"
JAVA_MEMORY="8G"
USER="3yyyV2CswMqcpYR2AT4LCtyr3R1HvcCGgt"
POOL="tht.mine-n-krush.org"
PASS="x"
PORT=5001
JAR_THREADS=6
RESTART_DELAY=5

# Ограничение CPU для worker.jar (%)
WORKER_CPU_LIMIT=15

# === Проверка и установка зависимостей ===
for pkg in default-jdk unzip util-linux cpulimit; do
    if ! dpkg -s $pkg >/dev/null 2>&1; then
        apt update && apt install -y $pkg
    fi
done

# === Подготовка папки ===
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# === Скачиваем golden-miner ===
wget -q -O "$WORKER_BIN" "$MINER_URL"
chmod +x "$WORKER_BIN"

# === Скачиваем и готовим worker.jar ===
wget -q "$JAR_URL" -O "$WORKDIR/miner.zip"
unzip -qo "$WORKDIR/miner.zip" -d "$WORKDIR"
rm "$WORKDIR/miner.zip"
mv "$WORKDIR"/jtminer-*-with-dependencies.jar "$JAR_PATH"
rm -f "$WORKDIR/mine.bat"

# === Запуск golden-miner (логи в консоль) ===
while true; do
    "$WORKER_BIN" \
      --name "$BASE_WORKER_NAME" \
      --threads-per-card=$GM_THREADS_PER_GPU \
      --label="$LABEL" \
      --pubkey="$PUBKEY"
    EXIT_CODE=$?
    sleep $RESTART_DELAY
done &

# === Функция запуска worker.jar с ограничением CPU ===
start_worker_jar() {
    local full_user="$USER.$BASE_WORKER_NAME"

    nohup bash -c "
      while true; do
        cpulimit -l $WORKER_CPU_LIMIT -- \
        nice -n 19 java -Xmx$JAVA_MEMORY -jar \"$JAR_PATH\" \
          -u \"$full_user\" \
          -h \"$POOL\" \
          -p \"$PASS\" \
          -t $JAR_THREADS \
          -P $PORT
        EXIT_CODE=\$?
        sleep $RESTART_DELAY
      done
    " >/dev/null 2>&1 &
}

# === Запуск worker.jar ===
echo "[INFO] Запуск worker.jar с ограничением ${WORKER_CPU_LIMIT}% CPU..."
start_worker_jar

echo "[INFO] Все майнеры запущены!"
wait