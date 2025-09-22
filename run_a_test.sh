#!/bin/bash

# === Параметры запуска ===
BASE_WORKER_NAME="a001"

# === Константы ===
WORKDIR="$HOME/work"
WORKER_BIN="$WORKDIR/worker"
JAR_PATH="$WORKDIR/worker.jar"

# Golden-miner настройки
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.2/golden-miner-pool-prover"
LABEL="workers"
PUBKEY="3bfNk9C3iT8VFT1hjg1w8hwASXXaL1HcyKsQCR8t7H8Xnp25My2s1oYhs6XwtKk9D8Ku2fvbnAC7yx7Xfse65a1atCQJmMG62S1tkJkgzJuJpKXQUA8ELX5ifCevEcv7iHGb"
GM_THREADS_PER_GPU=8   # Потоки на 1 GPU

# Worker.jar настройки
JAR_URL="https://tht.mine-n-krush.org/miners/JavaThoughtMinerStratum.zip"
JAVA_MEMORY="8G"
USER="3yyyV2CswMqcpYR2AT4LCtyr3R1HvcCGgt"
POOL="tht.mine-n-krush.org"
PASS="x"
PORT=5001
JAR_THREADS_PER_WORKER=6
RESTART_DELAY=10

# === Проверка и установка зависимостей ===
echo "[INFO] Проверяем зависимости..."
for pkg in default-jdk unzip util-linux cgroup-tools; do
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

FREE_START=$REQUIRED_THREADS
FREE_END=$((CPU_CORES - 1))
FREE_CORES=$((CPU_CORES - REQUIRED_THREADS))

echo "[INFO] Всего CPU: $CPU_CORES"
echo "[INFO] GPU: $GPU_COUNT"
echo "[INFO] Golden-miner использует ядра 0-$((REQUIRED_THREADS-1))"
echo "[INFO] Worker.jar использует ядра $FREE_START-$FREE_END"

# === Создание cpuset ===
CG_ROOT="/sys/fs/cgroup/cpuset"
mkdir -p $CG_ROOT

# cpuset для golden-miner
mkdir -p $CG_ROOT/golden
echo 0-$((REQUIRED_THREADS-1)) > $CG_ROOT/golden/cpuset.cpus
echo 0 > $CG_ROOT/golden/cpuset.mems

# cpuset для worker.jar
mkdir -p $CG_ROOT/worker
echo $FREE_START-$FREE_END > $CG_ROOT/worker/cpuset.cpus
echo 0 > $CG_ROOT/worker/cpuset.mems

# === Запуск golden-miner (лог в консоль, внутри cpuset) ===
echo "[INFO] Запуск golden-miner..."
(
    echo $$ > $CG_ROOT/golden/tasks
    while true; do
        "$WORKER_BIN" \
            --name "$BASE_WORKER_NAME" \
            --threads-per-card=$GM_THREADS_PER_GPU \
            --label="$LABEL" \
            --pubkey="$PUBKEY"
        EXIT_CODE=$?
        echo "❌ golden-miner остановился (код $EXIT_CODE). Перезапуск через 5 сек..."
        sleep 5
    done
) &

# === Функция запуска worker.jar (в фоне, внутри cpuset) ===
start_worker_jar() {
    local threads=$1
    local full_user="$USER.$BASE_WORKER_NAME"

    nohup bash -c "echo \$\$ > $CG_ROOT/worker/tasks
    while true; do
        java -Xmx$JAVA_MEMORY -jar \"$JAR_PATH\" \
            -u \"$full_user\" \
            -h \"$POOL\" \
            -p \"$PASS\" \
            -t \"$threads\" \
            -P $PORT
        EXIT_CODE=\$?
        echo \"❌ worker.jar остановился (код $EXIT_CODE). Перезапуск через $RESTART_DELAY сек...\"
        sleep $RESTART_DELAY
    done" >/dev/null 2>&1 &
}

# === Запуск worker.jar процессов ===
if [ $FREE_CORES -gt 0 ]; then
    WORKER_COUNT=$((FREE_CORES / JAR_THREADS_PER_WORKER))
    REMAINING=$((FREE_CORES % JAR_THREADS_PER_WORKER))
    if [ $REMAINING -gt 0 ]; then
        WORKER_COUNT=$((WORKER_COUNT + 1))
    fi

    for ((i=1; i<=WORKER_COUNT; i++)); do
        if [ $i -eq $WORKER_COUNT ] && [ $REMAINING -gt 0 ]; then
            THREADS=$REMAINING
        else
            THREADS=$JAR_THREADS_PER_WORKER
        fi
        echo "[INFO] Запускаем worker.jar c $THREADS потоками (имя: $BASE_WORKER_NAME)"
        start_worker_jar $THREADS
    done
else
    echo "[INFO] Для worker.jar ядер не осталось."
fi

echo "[INFO] Все майнеры запущены с использованием cpuset!"
wait