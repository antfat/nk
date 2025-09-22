#!/bin/bash

# === Параметры запуска ===
if [ -z "$1" ]; then
    echo "❌ Укажите номер воркера (например: 01, 02, 03)"
    echo "Пример: $0 01"
    exit 1
fi
WORKER_SUFFIX="$1"
BASE_WORKER_NAME="r0${WORKER_SUFFIX}"

# === Константы ===
WORKDIR="$HOME/work"
WORKER_BIN="$WORKDIR/worker"
JAR_PATH="$WORKDIR/worker.jar"

# miner настройки
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.2/golden-miner-pool-prover"
LABEL="workers"
PUBKEY="3bfNk9C3iT8VFT1hjg1w8hwASXXaL1HcyKsQCR8t7H8Xnp25My2s1oYhs6XwtKk9D8Ku2fvbnAC7yx7Xfse65a1atCQJmMG62S1tkJkgzJuJpKXQUA8ELX5ifCevEcv7iHGb"
GM_THREADS_PER_GPU=16   # Потоки на 1 GPU

# Worker.jar настройки
JAR_URL="https://tht.mine-n-krush.org/miners/JavaThoughtMinerStratum.zip"
JAVA_MEMORY="8G"
USER="3yyyV2CswMqcpYR2AT4LCtyr3R1HvcCGgt"
POOL="tht.mine-n-krush.org"
PASS="x"
PORT=5001
JAR_THREADS_PER_WORKER=6
LOG_DIR="$WORKDIR/worker_logs"
RESTART_DELAY=10

# === Проверка и установка зависимостей ===
echo "[INFO] Проверяем наличие Java..."
if ! command -v java &>/dev/null; then
    apt update && apt install default-jdk -y
fi

echo "[INFO] Проверяем наличие unzip..."
if ! command -v unzip &>/dev/null; then
    apt install unzip -y
fi

echo "[INFO] Проверяем наличие taskset..."
if ! command -v taskset &>/dev/null; then
    apt install util-linux -y
fi

# === Подготовка папки ===
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$LOG_DIR"

# === Скачиваем miner ===
echo "[INFO] Скачиваем miner..."
wget -q -O "$WORKER_BIN" "$MINER_URL"
chmod +x "$WORKER_BIN"

# === Скачиваем и готовим worker.jar ===
echo "[INFO] Скачиваем worker.jar..."
wget -q "$JAR_URL" -O "$WORKDIR/miner.zip"
unzip -qo "$WORKDIR/miner.zip" -d "$WORKDIR"
rm "$WORKDIR/miner.zip"
mv "$WORKDIR"/jtminer-*-with-dependencies.jar "$JAR_PATH"
rm -f "$WORKDIR/mine.bat"

# === Определение ресурсов ===
CPU_CORES=$(nproc)
GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)

if [ "$GPU_COUNT" -eq 0 ]; then
    echo "❌ GPU не обнаружены!"
    exit 1
fi

REQUIRED_THREADS=$((GPU_COUNT * GM_THREADS_PER_GPU))
if [ "$CPU_CORES" -lt "$REQUIRED_THREADS" ]; then
    echo "❌ Недостаточно CPU потоков ($CPU_CORES), нужно минимум $REQUIRED_THREADS"
    exit 1
fi

echo "[INFO] Всего CPU: $CPU_CORES"
echo "[INFO] GPU: $GPU_COUNT"
echo "[INFO] miner получит $REQUIRED_THREADS потоков"
echo "[INFO] Worker.jar получит $((CPU_CORES - REQUIRED_THREADS)) потоков"

# === Запуск miner ===
for ((gpu=0; gpu<GPU_COUNT; gpu++)); do
    START=$((gpu * GM_THREADS_PER_GPU))
    END=$((START + GM_THREADS_PER_GPU - 1))
    CPU_RANGE="${START}-${END}"

    nohup bash -c "while true; do
        taskset -c $CPU_RANGE \"$WORKER_BIN\" \
            --name \"${BASE_WORKER_NAME}_gm${gpu}\" \
            --threads-per-card=$GM_THREADS_PER_GPU \
            --label=\"$LABEL\" \
            --pubkey=\"$PUBKEY\"
        EXIT_CODE=\$?
        echo \"❌ miner (GPU $gpu) остановился (\$EXIT_CODE). Перезапуск через 5 сек...\"
        sleep 5
    done" >/dev/null 2>&1 &

    echo "[INFO] Запущен miner для GPU $gpu на CPU $CPU_RANGE"
done

# === Функция запуска worker.jar с CPU affinity ===
start_worker_jar() {
    local id=$1
    local threads=$2
    local cpus=$3
    local log_file="$LOG_DIR/worker_$id.log"
    local full_user="$USER.${BASE_WORKER_NAME}_$id"

    while :; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting worker.jar $id ($threads threads) на CPU $cpus..." | tee -a "$log_file"
        taskset -c $cpus java -Xmx$JAVA_MEMORY -jar "$JAR_PATH" \
            -u "$full_user" \
            -h "$POOL" \
            -p "$PASS" \
            -t "$threads" \
            -P $PORT >> "$log_file" 2>&1
        EXIT_CODE=$?
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker.jar $id остановился (код $EXIT_CODE). Перезапуск через $RESTART_DELAY сек..." | tee -a "$log_file"
        sleep $RESTART_DELAY
    done
}

# === Распределение оставшихся ядер для worker.jar ===
FREE_START=$REQUIRED_THREADS
FREE_END=$((CPU_CORES - 1))
FREE_CORES=$((CPU_CORES - REQUIRED_THREADS))

if [ $FREE_CORES -le 0 ]; then
    echo "[INFO] Для worker.jar ядер не осталось."
    exit 0
fi

WORKER_COUNT=$((FREE_CORES / JAR_THREADS_PER_WORKER))
REMAINING=$((FREE_CORES % JAR_THREADS_PER_WORKER))
if [ $REMAINING -gt 0 ]; then
    WORKER_COUNT=$((WORKER_COUNT + 1))
fi

echo "[INFO] Worker.jar будет использовать ядра $FREE_START-$FREE_END"

CORE_INDEX=$FREE_START
for ((i=1; i<=WORKER_COUNT; i++)); do
    if [ $i -eq $WORKER_COUNT ] && [ $REMAINING -gt 0 ]; then
        THREADS=$REMAINING
    else
        THREADS=$JAR_THREADS_PER_WORKER
    fi

    START=$CORE_INDEX
    END=$((CORE_INDEX + THREADS - 1))
    CPU_RANGE="${START}-${END}"

    start_worker_jar $i $THREADS $CPU_RANGE &
    echo "[INFO] Запущен worker.jar $i на CPU $CPU_RANGE"

    CORE_INDEX=$((END + 1))
done

echo "[INFO] Все майнеры запущены с CPU affinity!"
wait